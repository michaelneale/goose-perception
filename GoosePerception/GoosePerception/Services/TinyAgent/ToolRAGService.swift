//
// ToolRAGService.swift
//
// Embedding-based tool selection using curated examples.
// Uses BM25-style scoring for fast, accurate tool retrieval.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.goose.perception", category: "ToolRAG")

// MARK: - Data Structures

/// A curated example for tool selection
struct ToolExample: Codable {
    let question: String
    let tools: [String]
    let full_example: String
    
    /// Tokenized question for BM25 matching
    var tokens: [String] {
        tokenize(question)
    }
}

/// Result of tool RAG retrieval
struct ToolRAGResult {
    var selectedTools: Set<TinyAgentToolName>
    let examples: [ToolExample]
    let scores: [(TinyAgentToolName, Float)]
}

// MARK: - Tokenization

/// Simple tokenizer for BM25
private func tokenize(_ text: String) -> [String] {
    let lowercased = text.lowercased()
    // Remove punctuation and split
    let cleaned = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
    return cleaned.filter { $0.count > 1 }  // Remove single chars
}

// MARK: - ToolRAG Service

/// Service for selecting relevant tools based on user query using example matching
actor ToolRAGService {
    static let shared = ToolRAGService()
    
    /// Number of top examples to retrieve
    var topK: Int = 6
    
    /// Minimum score threshold for tool selection
    var threshold: Float = 0.1
    
    /// Loaded examples from JSON
    private var examples: [ToolExample] = []
    
    /// Precomputed IDF values for BM25
    private var idfValues: [String: Float] = [:]
    
    /// Average document length for BM25
    private var avgDocLength: Float = 0
    
    /// BM25 parameters
    private let k1: Float = 1.5
    private let b: Float = 0.75
    
    private init() {}
    
    // MARK: - Loading
    
    /// Load examples from bundled JSON
    func loadExamples() async throws {
        guard examples.isEmpty else { return }  // Already loaded
        
        // Try to load from bundle
        guard let url = Bundle.main.url(forResource: "tool_rag_examples", withExtension: "json") else {
            logger.warning("tool_rag_examples.json not found in bundle, using fallback")
            loadFallbackExamples()
            return
        }
        
        let data = try Data(contentsOf: url)
        examples = try JSONDecoder().decode([ToolExample].self, from: data)
        
        // Compute IDF values
        computeIDF()
        
        logger.info("Loaded \(self.examples.count) tool RAG examples")
    }
    
    /// Compute IDF values for all terms
    private func computeIDF() {
        var documentFrequency: [String: Int] = [:]
        var totalLength = 0
        
        for example in examples {
            let tokens = Set(example.tokens)  // Unique tokens per doc
            for token in tokens {
                documentFrequency[token, default: 0] += 1
            }
            totalLength += example.tokens.count
        }
        
        let n = Float(examples.count)
        avgDocLength = Float(totalLength) / n
        
        for (term, df) in documentFrequency {
            // IDF with smoothing
            idfValues[term] = log((n - Float(df) + 0.5) / (Float(df) + 0.5) + 1)
        }
    }
    
    /// Fallback examples when JSON not available
    private func loadFallbackExamples() {
        examples = [
            ToolExample(
                question: "Get John's phone number",
                tools: ["get_phone_number"],
                full_example: "Question: Get John's phone number.\n1. get_phone_number(\"John\")\n2. join()<END_OF_PLAN>"
            ),
            ToolExample(
                question: "Create a note titled Meeting Notes with bullet points",
                tools: ["create_note"],
                full_example: "Question: Create a note titled Meeting Notes.\n1. create_note(\"Meeting Notes\", \"- Item 1\\n- Item 2\", None)\n2. join()<END_OF_PLAN>"
            ),
            ToolExample(
                question: "Create a reminder to call mom tomorrow",
                tools: ["create_reminder"],
                full_example: "Question: Remind me to call mom tomorrow.\n1. create_reminder(\"Call mom\", \"tomorrow\", None, None)\n2. join()<END_OF_PLAN>"
            ),
            ToolExample(
                question: "Schedule a meeting with the team tomorrow at 2 PM",
                tools: ["create_calendar_event"],
                full_example: "Question: Schedule a meeting tomorrow at 2 PM.\n1. create_calendar_event(\"Team Meeting\", \"2024-01-15 14:00:00\", \"2024-01-15 15:00:00\", \"\", [], \"\", None)\n2. join()<END_OF_PLAN>"
            ),
            ToolExample(
                question: "Text Sarah about the meeting change",
                tools: ["get_phone_number", "send_sms"],
                full_example: "Question: Text Sarah about the meeting.\n1. get_phone_number(\"Sarah\")\n2. send_sms([$1], \"Meeting time changed\")\n3. join()<END_OF_PLAN>"
            ),
            ToolExample(
                question: "Show me directions to Apple Park",
                tools: ["maps_show_directions"],
                full_example: "Question: Show directions to Apple Park.\n1. maps_show_directions(\"\", \"Apple Park\", \"d\")\n2. join()<END_OF_PLAN>"
            ),
            ToolExample(
                question: "Find the nearest coffee shop",
                tools: ["maps_open_location"],
                full_example: "Question: Find nearest coffee shop.\n1. maps_open_location(\"coffee shop\")\n2. join()<END_OF_PLAN>"
            ),
            ToolExample(
                question: "Open the note called Project Ideas",
                tools: ["open_note"],
                full_example: "Question: Open the note Project Ideas.\n1. open_note(\"Project Ideas\", None)\n2. join()<END_OF_PLAN>"
            ),
            ToolExample(
                question: "Add more items to my shopping list note",
                tools: ["append_note_content"],
                full_example: "Question: Add to shopping list note.\n1. append_note_content(\"Shopping List\", \"- More items\", None)\n2. join()<END_OF_PLAN>"
            ),
            ToolExample(
                question: "Email the project update to the team",
                tools: ["compose_new_email"],
                full_example: "Question: Email project update.\n1. compose_new_email([\"team@example.com\"], [], \"Project Update\", \"Here is the update.\", [])\n2. join()<END_OF_PLAN>"
            ),
        ]
        computeIDF()
    }
    
    // MARK: - Tool Selection
    
    /// Select relevant tools for a query using BM25 example matching
    func selectTools(for query: String) async -> ToolRAGResult {
        // Ensure examples are loaded
        if examples.isEmpty {
            try? await loadExamples()
        }
        
        let queryTokens = tokenize(query)
        
        // Score all examples using BM25
        var exampleScores: [(ToolExample, Float)] = []
        
        for example in examples {
            let score = bm25Score(queryTokens: queryTokens, docTokens: example.tokens)
            if score > 0 {
                exampleScores.append((example, score))
            }
        }
        
        // Sort by score and take top K
        exampleScores.sort { $0.1 > $1.1 }
        let topExamples = Array(exampleScores.prefix(topK))
        
        // Aggregate tool scores from top examples
        var toolScores: [TinyAgentToolName: Float] = [:]
        var toolCounts: [TinyAgentToolName: Int] = [:]
        
        for (example, score) in topExamples {
            for toolName in example.tools {
                if let tool = TinyAgentToolName(rawValue: toolName) {
                    toolScores[tool, default: 0] += score
                    toolCounts[tool, default: 0] += 1
                }
            }
        }
        
        // Normalize scores
        let maxScore = toolScores.values.max() ?? 1.0
        for (tool, score) in toolScores {
            toolScores[tool] = score / maxScore
        }
        
        // Apply intent-based filtering
        let filteredScores = applyIntentFiltering(query: query, scores: toolScores)
        
        // Select tools above threshold
        let selectedTools = Set(filteredScores.filter { $0.value >= threshold }.map { $0.key })
        
        // Get sorted scores for debugging
        let sortedScores = filteredScores
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
        
        logger.debug("Query: \(query)")
        logger.debug("Top tools: \(sortedScores.prefix(5).map { "\($0.0.rawValue): \(String(format: "%.2f", $0.1))" }.joined(separator: ", "))")
        
        return ToolRAGResult(
            selectedTools: selectedTools,
            examples: topExamples.map { $0.0 },
            scores: sortedScores
        )
    }
    
    /// Compute BM25 score between query and document
    private func bm25Score(queryTokens: [String], docTokens: [String]) -> Float {
        let docLength = Float(docTokens.count)
        let docTokenCounts = Dictionary(grouping: docTokens) { $0 }.mapValues { $0.count }
        
        var score: Float = 0
        
        for token in Set(queryTokens) {
            guard let tf = docTokenCounts[token] else { continue }
            let idf = idfValues[token] ?? 0
            
            let tfNorm = (Float(tf) * (k1 + 1)) / (Float(tf) + k1 * (1 - b + b * docLength / avgDocLength))
            score += idf * tfNorm
        }
        
        return score
    }
    
    /// Apply intent-based filtering to handle ambiguous cases
    private func applyIntentFiltering(query: String, scores: [TinyAgentToolName: Float]) -> [TinyAgentToolName: Float] {
        var filtered = scores
        let queryLower = query.lowercased()
        
        // Intent detection patterns
        let createIntent = queryLower.contains("create") || queryLower.contains("new") || 
                          queryLower.contains("make") || queryLower.contains("write")
        let openIntent = queryLower.contains("open") || queryLower.contains("show") || 
                        queryLower.contains("view") || queryLower.contains("read")
        let appendIntent = queryLower.contains("add to") || queryLower.contains("append") || 
                          queryLower.contains("update") || queryLower.contains("extend")
        
        // Notes: disambiguate create vs open vs append
        if createIntent && !openIntent && !appendIntent {
            // Boost create_note, suppress open_note and append_note_content
            filtered[.createNote] = (filtered[.createNote] ?? 0) + 0.3
            filtered[.openNote] = (filtered[.openNote] ?? 0) * 0.3
            filtered[.appendNoteContent] = (filtered[.appendNoteContent] ?? 0) * 0.3
        } else if openIntent && !createIntent && !appendIntent {
            filtered[.openNote] = (filtered[.openNote] ?? 0) + 0.3
            filtered[.createNote] = (filtered[.createNote] ?? 0) * 0.5
        } else if appendIntent {
            filtered[.appendNoteContent] = (filtered[.appendNoteContent] ?? 0) + 0.3
            filtered[.createNote] = (filtered[.createNote] ?? 0) * 0.5
        }
        
        // SMS vs Email disambiguation
        let smsIntent = queryLower.contains("text") || queryLower.contains("sms") || 
                       queryLower.contains("message") || queryLower.contains("imessage")
        let emailIntent = queryLower.contains("email") || queryLower.contains("mail")
        
        if smsIntent && !emailIntent {
            filtered[.sendSMS] = (filtered[.sendSMS] ?? 0) + 0.2
            filtered[.composeNewEmail] = (filtered[.composeNewEmail] ?? 0) * 0.3
        } else if emailIntent && !smsIntent {
            filtered[.composeNewEmail] = (filtered[.composeNewEmail] ?? 0) + 0.2
            filtered[.sendSMS] = (filtered[.sendSMS] ?? 0) * 0.3
        }
        
        // Directions vs Location
        let directionsIntent = queryLower.contains("direction") || queryLower.contains("how to get") ||
                              queryLower.contains("route") || queryLower.contains("navigate")
        let locationIntent = queryLower.contains("find") || queryLower.contains("where") ||
                            queryLower.contains("nearest") || queryLower.contains("locate")
        
        if directionsIntent && !locationIntent {
            filtered[.mapsShowDirections] = (filtered[.mapsShowDirections] ?? 0) + 0.2
            filtered[.mapsOpenLocation] = (filtered[.mapsOpenLocation] ?? 0) * 0.5
        } else if locationIntent && !directionsIntent {
            filtered[.mapsOpenLocation] = (filtered[.mapsOpenLocation] ?? 0) + 0.2
        }
        
        return filtered
    }
    
    // MARK: - In-Context Examples
    
    /// Get formatted in-context examples for the selected tools
    func getExamplesPrompt(for result: ToolRAGResult, maxExamples: Int = 3) -> String {
        let relevantExamples = result.examples
            .filter { example in
                // Only include examples that use selected tools
                example.tools.contains { toolName in
                    result.selectedTools.contains { $0.rawValue == toolName }
                }
            }
            .prefix(maxExamples)
        
        if relevantExamples.isEmpty {
            return ""
        }
        
        return relevantExamples.map { $0.full_example }.joined(separator: "\n###\n")
    }
    
}


// MARK: - Prompt Building Extension

extension ToolRAGService {
    
    /// Build the system prompt with selected tools and examples
    func buildSystemPrompt(for result: ToolRAGResult) async -> String {
        let toolsPrompt = await ToolRegistry.shared.generateToolsPrompt(for: result.selectedTools)
        let examples = getExamplesPrompt(for: result)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let currentDate = dateFormatter.string(from: Date())
        
        return """
            Given a user query, create a plan to solve it with the utmost parallelizability.
            Each plan should comprise an action from the following types:
            
            \(toolsPrompt)
            
            Guidelines:
             - Each action described above contains input/output types and description.
                - You must strictly adhere to the input and output types for each action.
                - The action descriptions contain the guidelines. You MUST strictly follow those guidelines when you use the actions.
             - Each action in the plan should strictly be one of the above types. Follow the Python conventions for each action.
             - Each action MUST have a unique ID, which is strictly increasing.
             - Inputs for actions can either be constants or outputs from preceding actions. In the latter case, use the format $id to denote the ID of the previous action whose output will be the input.
             - Always call join as the last action in the plan. Say '<END_OF_PLAN>' after you call join
             - Ensure the plan maximizes parallelizability.
             - Only use the provided action types. If a query cannot be addressed using these, invoke the join action for the next steps.
             - Never explain the plan with comments (e.g. #).
             - Never introduce new actions other than the ones provided.
            
            Custom Instructions:
             - You need to start your plan with the '1.' call
             - Today's date is \(currentDate)
             - Unless otherwise specified, the default meeting duration is 60 minutes.
             - Do not use named arguments in your tool calls.
             - You MUST end your plans with the 'join()' call and a '\\n' character.
             - You MUST fill every argument in the tool calls, even if they are optional.
             - The format for dates MUST be in ISO format of 'YYYY-MM-DD HH:MM:SS', unless other specified.
             - If you want to use the result of a previous tool call, you MUST use the '$' sign followed by the index of the tool call.
             - You MUST ONLY USE join() at the very very end of the plan, or you WILL BE PENALIZED.
            
            Here are some examples:
            
            \(examples)
            """
    }
}
