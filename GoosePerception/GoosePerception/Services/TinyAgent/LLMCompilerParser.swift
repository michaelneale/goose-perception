//
// LLMCompilerParser.swift
//
// Parses TinyAgent LLMCompiler output format into executable tasks.
//
// Expected format:
// 1. tool_name("arg1", "arg2")
// 2. another_tool($1, "arg")
// Thought: optional reasoning
// 3. join()<END_OF_PLAN>
//

import Foundation

/// A parsed task from LLMCompiler output
struct ParsedTask: Identifiable {
    let id: Int
    let toolName: String
    let arguments: [TaskArgument]
    let thought: String?
    
    /// Check if this is the join() task
    var isJoin: Bool {
        toolName == "join"
    }
    
    /// Get dependencies (task IDs this task depends on)
    var dependencies: [Int] {
        arguments.compactMap { arg in
            if case .reference(let taskId) = arg {
                return taskId
            }
            return nil
        }
    }
}

/// An argument to a task - either a literal value or a reference to another task's output
enum TaskArgument: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([TaskArgument])
    case null
    case reference(Int)  // $1, $2, etc. - reference to another task's output
    
    /// Resolve the argument to a concrete value, substituting references
    func resolve(with outputs: [Int: String]) -> Any? {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return nil
        case .array(let arr): return arr.map { $0.resolve(with: outputs) }
        case .reference(let taskId):
            return outputs[taskId]
        }
    }
}

/// Result of parsing LLMCompiler output
struct ParseResult {
    let tasks: [ParsedTask]
    let thoughts: [String]
    let hasEndOfPlan: Bool
    let parseErrors: [String]
    
    var isValid: Bool {
        !tasks.isEmpty && hasEndOfPlan && parseErrors.isEmpty
    }
}

/// Parser for LLMCompiler output format
struct LLMCompilerParser {
    
    // Regex patterns
    private static let actionPattern = try! NSRegularExpression(
        pattern: #"^\s*(\d+)\.\s*(\w+)\((.*)\)\s*(?:#.*)?$"#,
        options: [.anchorsMatchLines]
    )
    
    private static let thoughtPattern = try! NSRegularExpression(
        pattern: #"^Thought:\s*(.*)$"#,
        options: [.anchorsMatchLines, .caseInsensitive]
    )
    
    private static let referencePattern = try! NSRegularExpression(
        pattern: #"\$\{?(\d+)\}?"#,
        options: []
    )
    
    private static let endOfPlanMarker = "<END_OF_PLAN>"
    
    /// Split output into logical lines, respecting quoted strings
    /// This handles cases where string arguments contain newlines
    private func splitIntoLogicalLines(_ text: String) -> [String] {
        var lines: [String] = []
        var currentLine = ""
        var inQuote = false
        var escapeNext = false
        
        for char in text {
            if escapeNext {
                currentLine.append(char)
                escapeNext = false
                continue
            }
            
            if char == "\\" {
                currentLine.append(char)
                escapeNext = true
                continue
            }
            
            if char == "\"" {
                inQuote = !inQuote
                currentLine.append(char)
                continue
            }
            
            if char == "\n" && !inQuote {
                // End of logical line (outside quotes)
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                }
                currentLine = ""
                continue
            }
            
            currentLine.append(char)
        }
        
        // Don't forget the last line
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines
    }
    
    /// Parse LLMCompiler output into tasks
    func parse(_ output: String) -> ParseResult {
        var tasks: [ParsedTask] = []
        var thoughts: [String] = []
        var parseErrors: [String] = []
        var currentThought: String? = nil
        
        let hasEndOfPlan = output.contains(Self.endOfPlanMarker)
        
        // Clean output
        let cleanedOutput = output
            .replacingOccurrences(of: Self.endOfPlanMarker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Use logical line splitting that respects quoted strings
        let lines = splitIntoLogicalLines(cleanedOutput)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            if trimmedLine.isEmpty { continue }
            
            // Check for Thought:
            if let thoughtMatch = Self.thoughtPattern.firstMatch(
                in: trimmedLine,
                options: [],
                range: NSRange(trimmedLine.startIndex..., in: trimmedLine)
            ) {
                if let thoughtRange = Range(thoughtMatch.range(at: 1), in: trimmedLine) {
                    currentThought = String(trimmedLine[thoughtRange])
                    thoughts.append(currentThought!)
                }
                continue
            }
            
            // Check for action
            if let actionMatch = Self.actionPattern.firstMatch(
                in: trimmedLine,
                options: [],
                range: NSRange(trimmedLine.startIndex..., in: trimmedLine)
            ) {
                guard let idRange = Range(actionMatch.range(at: 1), in: trimmedLine),
                      let nameRange = Range(actionMatch.range(at: 2), in: trimmedLine),
                      let argsRange = Range(actionMatch.range(at: 3), in: trimmedLine) else {
                    parseErrors.append("Failed to parse action: \(trimmedLine)")
                    continue
                }
                
                let idStr = String(trimmedLine[idRange])
                let toolName = String(trimmedLine[nameRange])
                let argsStr = String(trimmedLine[argsRange])
                
                guard let id = Int(idStr) else {
                    parseErrors.append("Invalid task ID: \(idStr)")
                    continue
                }
                
                do {
                    let arguments = try parseArguments(argsStr)
                    let task = ParsedTask(
                        id: id,
                        toolName: toolName,
                        arguments: arguments,
                        thought: currentThought
                    )
                    tasks.append(task)
                    currentThought = nil
                } catch {
                    parseErrors.append("Failed to parse arguments for task \(id): \(error.localizedDescription)")
                }
                
                continue
            }
            
            // Unknown line format
            if !trimmedLine.hasPrefix("#") {
                // Not a comment, might be an error
                // But don't add parse errors for minor things
            }
        }
        
        return ParseResult(
            tasks: tasks,
            thoughts: thoughts,
            hasEndOfPlan: hasEndOfPlan,
            parseErrors: parseErrors
        )
    }
    
    /// Parse arguments string into TaskArgument array
    private func parseArguments(_ argsStr: String) throws -> [TaskArgument] {
        let trimmed = argsStr.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return []
        }
        
        var arguments: [TaskArgument] = []
        var current = ""
        var inString = false
        var stringDelimiter: Character = "\""
        var bracketDepth = 0
        var escapeNext = false
        
        for char in trimmed {
            if escapeNext {
                current.append(char)
                escapeNext = false
                continue
            }
            
            if char == "\\" {
                escapeNext = true
                current.append(char)
                continue
            }
            
            if !inString {
                if char == "\"" || char == "'" {
                    inString = true
                    stringDelimiter = char
                    current.append(char)
                } else if char == "[" {
                    bracketDepth += 1
                    current.append(char)
                } else if char == "]" {
                    bracketDepth -= 1
                    current.append(char)
                } else if char == "," && bracketDepth == 0 {
                    // End of argument
                    if let arg = parseArgument(current.trimmingCharacters(in: .whitespaces)) {
                        arguments.append(arg)
                    }
                    current = ""
                } else {
                    current.append(char)
                }
            } else {
                current.append(char)
                if char == stringDelimiter {
                    inString = false
                }
            }
        }
        
        // Handle last argument
        let lastArg = current.trimmingCharacters(in: .whitespaces)
        if !lastArg.isEmpty {
            if let arg = parseArgument(lastArg) {
                arguments.append(arg)
            }
        }
        
        return arguments
    }
    
    /// Parse a single argument value
    private func parseArgument(_ value: String) -> TaskArgument? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        
        if trimmed.isEmpty {
            return nil
        }
        
        // Check for reference ($1, ${1})
        if let refMatch = Self.referencePattern.firstMatch(
            in: trimmed,
            options: [],
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ) {
            if let idRange = Range(refMatch.range(at: 1), in: trimmed),
               let taskId = Int(String(trimmed[idRange])) {
                return .reference(taskId)
            }
        }
        
        // Check for string (quoted)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            let inner = String(trimmed.dropFirst().dropLast())
            return .string(unescapeString(inner))
        }
        
        // Check for None/null
        if trimmed == "None" || trimmed == "null" || trimmed == "nil" {
            return .null
        }
        
        // Check for boolean
        if trimmed == "True" || trimmed == "true" {
            return .bool(true)
        }
        if trimmed == "False" || trimmed == "false" {
            return .bool(false)
        }
        
        // Check for array
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            if inner.isEmpty {
                return .array([])
            }
            do {
                let elements = try parseArguments(inner)
                return .array(elements)
            } catch {
                return .string(trimmed)
            }
        }
        
        // Check for integer
        if let intVal = Int(trimmed) {
            return .int(intVal)
        }
        
        // Check for double
        if let doubleVal = Double(trimmed) {
            return .double(doubleVal)
        }
        
        // Default to string
        return .string(trimmed)
    }
    
    /// Unescape string characters
    private func unescapeString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\"", with: "\"")
         .replacingOccurrences(of: "\\'", with: "'")
         .replacingOccurrences(of: "\\n", with: "\n")
         .replacingOccurrences(of: "\\r", with: "\r")
         .replacingOccurrences(of: "\\t", with: "\t")
         .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

// MARK: - Joinner Output Parser

/// Result of joinner evaluation
enum JoinnerDecision {
    case finish(String)
    case replan(String?)
}

struct JoinnerOutputParser {
    
    private static let finishPattern = try! NSRegularExpression(
        pattern: #"Action:\s*Finish\((.+)\)"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    
    private static let replanPattern = try! NSRegularExpression(
        pattern: #"Action:\s*Replan"#,
        options: [.caseInsensitive]
    )
    
    private static let thoughtPattern = try! NSRegularExpression(
        pattern: #"Thought:\s*(.+?)(?=Action:|$)"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    
    func parse(_ output: String) -> JoinnerDecision {
        // Check for Replan first
        if Self.replanPattern.firstMatch(
            in: output,
            options: [],
            range: NSRange(output.startIndex..., in: output)
        ) != nil {
            // Extract thought if present
            var thought: String? = nil
            if let thoughtMatch = Self.thoughtPattern.firstMatch(
                in: output,
                options: [],
                range: NSRange(output.startIndex..., in: output)
            ) {
                if let thoughtRange = Range(thoughtMatch.range(at: 1), in: output) {
                    thought = String(output[thoughtRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return .replan(thought)
        }
        
        // Check for Finish
        if let finishMatch = Self.finishPattern.firstMatch(
            in: output,
            options: [],
            range: NSRange(output.startIndex..., in: output)
        ) {
            if let answerRange = Range(finishMatch.range(at: 1), in: output) {
                let answer = String(output[answerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                return .finish(answer)
            }
        }
        
        // Default to finish with the whole output
        return .finish(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
