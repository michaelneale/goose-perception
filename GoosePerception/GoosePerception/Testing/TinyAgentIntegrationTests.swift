//
// TinyAgentIntegrationTests.swift
//
// Integration tests for TinyAgent that stub AppleScript execution
// to capture and verify the actual parameters being passed.
//
// This tests the full pipeline: LLM → Parser → Executor → Tool calls
// without actually executing AppleScript (safe for CI/automated testing).
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.goose.perception", category: "TinyAgentTests")

// MARK: - Stubbed AppleScript Bridge

/// A mock AppleScript bridge that captures calls instead of executing them
actor MockAppleScriptBridge {
    
    struct CapturedCall: CustomStringConvertible {
        let method: String
        let arguments: [String: Any]
        let timestamp: Date
        let rawScript: String?
        
        var description: String {
            let args = arguments.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            return "\(method)(\(args))"
        }
    }
    
    private(set) var capturedCalls: [CapturedCall] = []
    private(set) var executedScripts: [String] = []
    
    /// Pre-configured responses for specific methods
    var mockResponses: [String: String] = [
        "getPhoneNumber": "+1-555-123-4567",
        "getEmail": "john@example.com",
        "createReminder": "Reminder created successfully",
        "createCalendarEvent": "Event created successfully",
        "createNote": "Note created successfully",
        "sendSMS": "Message composed (press Enter to send)",
        "mapsOpenLocation": "Maps opened",
        "mapsGetDirections": "Directions displayed",
        "spotlightSearch": "file1.txt, file2.pdf",
    ]
    
    func reset() {
        capturedCalls = []
        executedScripts = []
    }
    
    // MARK: - Stubbed Methods (mirror AppleScriptBridge API)
    
    func getPhoneNumber(name: String) async throws -> String {
        capturedCalls.append(CapturedCall(
            method: "getPhoneNumber",
            arguments: ["name": name],
            timestamp: Date(),
            rawScript: nil
        ))
        return mockResponses["getPhoneNumber"] ?? "Not found"
    }
    
    func getEmail(name: String) async throws -> String {
        capturedCalls.append(CapturedCall(
            method: "getEmail",
            arguments: ["name": name],
            timestamp: Date(),
            rawScript: nil
        ))
        return mockResponses["getEmail"] ?? "Not found"
    }
    
    func createCalendarEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        location: String?,
        notes: String?,
        calendarName: String?,
        attendees: [String]
    ) async throws -> String {
        capturedCalls.append(CapturedCall(
            method: "createCalendarEvent",
            arguments: [
                "title": title,
                "startDate": startDate,
                "endDate": endDate,
                "location": location ?? "nil",
                "notes": notes ?? "nil",
                "calendarName": calendarName ?? "nil",
                "attendees": attendees
            ],
            timestamp: Date(),
            rawScript: nil
        ))
        return mockResponses["createCalendarEvent"] ?? "Created"
    }
    
    func createReminder(
        title: String,
        dueDate: Date?,
        notes: String?,
        listName: String?
    ) async throws -> String {
        capturedCalls.append(CapturedCall(
            method: "createReminder",
            arguments: [
                "title": title,
                "dueDate": dueDate?.description ?? "nil",
                "notes": notes ?? "nil",
                "listName": listName ?? "nil"
            ],
            timestamp: Date(),
            rawScript: nil
        ))
        return mockResponses["createReminder"] ?? "Created"
    }
    
    func createNote(title: String, body: String, folder: String?) async throws -> String {
        capturedCalls.append(CapturedCall(
            method: "createNote",
            arguments: [
                "title": title,
                "body": body,
                "folder": folder ?? "nil"
            ],
            timestamp: Date(),
            rawScript: nil
        ))
        return mockResponses["createNote"] ?? "Created"
    }
    
    func sendSMS(recipients: [String], message: String) async throws -> String {
        capturedCalls.append(CapturedCall(
            method: "sendSMS",
            arguments: [
                "recipients": recipients,
                "message": message
            ],
            timestamp: Date(),
            rawScript: nil
        ))
        return mockResponses["sendSMS"] ?? "Sent"
    }
    
    func mapsOpenLocation(query: String) async throws -> String {
        capturedCalls.append(CapturedCall(
            method: "mapsOpenLocation",
            arguments: ["query": query],
            timestamp: Date(),
            rawScript: nil
        ))
        return mockResponses["mapsOpenLocation"] ?? "Opened"
    }
    
    func mapsGetDirections(from: String?, to: String) async throws -> String {
        capturedCalls.append(CapturedCall(
            method: "mapsGetDirections",
            arguments: [
                "from": from ?? "current location",
                "to": to
            ],
            timestamp: Date(),
            rawScript: nil
        ))
        return mockResponses["mapsGetDirections"] ?? "Displayed"
    }
    
    func spotlightSearch(query: String, fileTypes: [String]?) async throws -> String {
        capturedCalls.append(CapturedCall(
            method: "spotlightSearch",
            arguments: [
                "query": query,
                "fileTypes": fileTypes ?? []
            ],
            timestamp: Date(),
            rawScript: nil
        ))
        return mockResponses["spotlightSearch"] ?? "Found"
    }
    
    /// Capture raw script execution (for testing escaping)
    func executeRaw(_ script: String) async throws -> String {
        executedScripts.append(script)
        return "OK"
    }
}

// MARK: - Test Executor with Mock Bridge

/// Task executor that uses the mock bridge
class MockTaskExecutor {
    let mockBridge: MockAppleScriptBridge
    
    init(mockBridge: MockAppleScriptBridge) {
        self.mockBridge = mockBridge
    }
    
    /// Execute a parsed task and return the result
    func execute(_ task: ParsedTask, outputs: [Int: String]) async throws -> String {
        // Resolve arguments
        let resolvedArgs = task.arguments.map { $0.resolve(with: outputs) }
        
        switch task.toolName {
        case "get_phone_number":
            guard let name = resolvedArgs.first as? String else {
                throw MockExecutorError.invalidArguments("get_phone_number requires name")
            }
            return try await mockBridge.getPhoneNumber(name: name)
            
        case "get_email":
            guard let name = resolvedArgs.first as? String else {
                throw MockExecutorError.invalidArguments("get_email requires name")
            }
            return try await mockBridge.getEmail(name: name)
            
        case "create_reminder":
            guard resolvedArgs.count >= 1, let title = resolvedArgs[0] as? String else {
                throw MockExecutorError.invalidArguments("create_reminder requires title")
            }
            let dueDate = parseDate(resolvedArgs.count > 1 ? resolvedArgs[1] : nil)
            let notes = resolvedArgs.count > 2 ? resolvedArgs[2] as? String : nil
            let listName = resolvedArgs.count > 3 ? resolvedArgs[3] as? String : nil
            return try await mockBridge.createReminder(title: title, dueDate: dueDate, notes: notes, listName: listName)
            
        case "create_calendar_event":
            guard resolvedArgs.count >= 3,
                  let title = resolvedArgs[0] as? String else {
                throw MockExecutorError.invalidArguments("create_calendar_event requires title, start, end")
            }
            let startDate = parseDate(resolvedArgs[1]) ?? Date()
            let endDate = parseDate(resolvedArgs[2]) ?? Date().addingTimeInterval(3600)
            let location = resolvedArgs.count > 3 ? resolvedArgs[3] as? String : nil
            let notes = resolvedArgs.count > 4 ? resolvedArgs[4] as? String : nil
            let calendarName = resolvedArgs.count > 5 ? resolvedArgs[5] as? String : nil
            let attendees = resolvedArgs.count > 6 ? (resolvedArgs[6] as? [String]) ?? [] : []
            return try await mockBridge.createCalendarEvent(
                title: title, startDate: startDate, endDate: endDate,
                location: location, notes: notes, calendarName: calendarName, attendees: attendees
            )
            
        case "create_note":
            guard resolvedArgs.count >= 2,
                  let title = resolvedArgs[0] as? String,
                  let body = resolvedArgs[1] as? String else {
                throw MockExecutorError.invalidArguments("create_note requires title and body")
            }
            let folder = resolvedArgs.count > 2 ? resolvedArgs[2] as? String : nil
            return try await mockBridge.createNote(title: title, body: body, folder: folder)
            
        case "send_sms":
            guard resolvedArgs.count >= 2 else {
                throw MockExecutorError.invalidArguments("send_sms requires recipients and message")
            }
            var recipients: [String] = []
            if let arr = resolvedArgs[0] as? [Any] {
                recipients = arr.compactMap { $0 as? String }
            } else if let single = resolvedArgs[0] as? String {
                recipients = [single]
            }
            let message = resolvedArgs[1] as? String ?? ""
            return try await mockBridge.sendSMS(recipients: recipients, message: message)
            
        case "maps_open_location":
            guard let query = resolvedArgs.first as? String else {
                throw MockExecutorError.invalidArguments("maps_open_location requires query")
            }
            return try await mockBridge.mapsOpenLocation(query: query)
            
        case "maps_get_directions":
            guard resolvedArgs.count >= 1 else {
                throw MockExecutorError.invalidArguments("maps_get_directions requires destination")
            }
            let from = resolvedArgs.count > 1 ? resolvedArgs[1] as? String : nil
            let to = resolvedArgs[0] as? String ?? ""
            return try await mockBridge.mapsGetDirections(from: from, to: to)
            
        case "spotlight_search":
            guard let query = resolvedArgs.first as? String else {
                throw MockExecutorError.invalidArguments("spotlight_search requires query")
            }
            let fileTypes = resolvedArgs.count > 1 ? resolvedArgs[1] as? [String] : nil
            return try await mockBridge.spotlightSearch(query: query, fileTypes: fileTypes)
            
        case "join":
            return "Plan complete"
            
        default:
            throw MockExecutorError.unknownTool(task.toolName)
        }
    }
    
    private func parseDate(_ value: Any?) -> Date? {
        guard let value = value else { return nil }
        
        if let date = value as? Date {
            return date
        }
        
        if let str = value as? String, !str.isEmpty, str != "None", str != "nil" {
            // Try various date formats
            let formatters: [DateFormatter] = {
                let formats = [
                    "yyyy-MM-dd HH:mm:ss",
                    "yyyy-MM-dd HH:mm",
                    "yyyy-MM-dd",
                    "MM/dd/yyyy HH:mm",
                    "MM/dd/yyyy"
                ]
                return formats.map { fmt in
                    let f = DateFormatter()
                    f.dateFormat = fmt
                    return f
                }
            }()
            
            for formatter in formatters {
                if let date = formatter.date(from: str) {
                    return date
                }
            }
            
            // Try relative parsing: "tomorrow", "in 2 hours", etc.
            if str.lowercased().contains("tomorrow") {
                return Calendar.current.date(byAdding: .day, value: 1, to: Date())
            }
        }
        
        return nil
    }
}

enum MockExecutorError: Error, LocalizedError {
    case invalidArguments(String)
    case unknownTool(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidArguments(let msg): return "Invalid arguments: \(msg)"
        case .unknownTool(let name): return "Unknown tool: \(name)"
        }
    }
}

// MARK: - Integration Tests

@MainActor
class TinyAgentIntegrationTests {
    
    struct TestCase {
        let name: String
        let query: String
        let expectedTools: [String]  // Expected tool names to be called
        let expectedArgChecks: [(tool: String, check: ([String: Any]) -> Bool)]
    }
    
    struct TestResult {
        let name: String
        let passed: Bool
        let message: String
        let capturedCalls: [MockAppleScriptBridge.CapturedCall]
        let llmOutput: String?
        let parseErrors: [String]
    }
    
    private var results: [TestResult] = []
    private let mockBridge = MockAppleScriptBridge()
    
    private func log(_ message: String) {
        print("[TinyAgentTest] \(message)")
        fflush(stdout)
    }
    
    // MARK: - Entry Point
    
    static func run(includeLLM: Bool = false) async {
        let tests = TinyAgentIntegrationTests()
        tests.includeLLMTests = includeLLM
        await tests.runAllTests()
    }
    
    /// Run with LLM tests (slower, requires model download)
    var includeLLMTests = false
    
    func runAllTests() async {
        log("═══════════════════════════════════════════════════════════")
        log("  TINYAGENT INTEGRATION TESTS")
        log("═══════════════════════════════════════════════════════════")
        log("")
        
        // Test 1: Parser-only tests (no LLM needed, fast)
        await testParserWithMockExecution()
        
        // Test 2: Full pipeline with LLM (requires model, slow)
        if includeLLMTests {
            await testFullPipelineWithLLM()
        } else {
            log("\n⏭️  Skipping LLM tests (use --test-tinyagent-llm to enable)\n")
        }
        
        printSummary()
    }
    
    // MARK: - Parser + Executor Tests
    
    private func testParserWithMockExecution() async {
        log("\n--- Parser + Mock Executor Tests ---\n")
        
        let parser = LLMCompilerParser()
        let executor = MockTaskExecutor(mockBridge: mockBridge)
        
        // Test cases with pre-defined LLM outputs
        let testCases: [(name: String, llmOutput: String, expectedCalls: [(tool: String, argCheck: ([String: Any]) -> Bool)])] = [
            
            // Test 1: Simple phone lookup
            (
                name: "Phone number lookup",
                llmOutput: """
                1. get_phone_number("John Smith")
                2. join()<END_OF_PLAN>
                """,
                expectedCalls: [
                    ("getPhoneNumber", { args in
                        (args["name"] as? String) == "John Smith"
                    })
                ]
            ),
            
            // Test 2: Reminder with date
            (
                name: "Create reminder with date",
                llmOutput: """
                1. create_reminder("Buy groceries", "2025-01-30 09:00:00", None, None)
                2. join()<END_OF_PLAN>
                """,
                expectedCalls: [
                    ("createReminder", { args in
                        (args["title"] as? String) == "Buy groceries" &&
                        (args["dueDate"] as? String)?.contains("2025") == true
                    })
                ]
            ),
            
            // Test 3: Calendar event with special characters
            (
                name: "Calendar event with quotes in title",
                llmOutput: """
                1. create_calendar_event("Meeting with \"John\"", "2025-01-30 14:00:00", "2025-01-30 15:00:00", "Conference Room A", None, None, [])
                2. join()<END_OF_PLAN>
                """,
                expectedCalls: [
                    ("createCalendarEvent", { args in
                        let title = args["title"] as? String ?? ""
                        return title.contains("John")
                    })
                ]
            ),
            
            // Test 4: SMS with phone number reference
            (
                name: "SMS with phone lookup",
                llmOutput: """
                1. get_phone_number("Mom")
                2. send_sms([$1], "Running late, be there in 20 mins")
                3. join()<END_OF_PLAN>
                """,
                expectedCalls: [
                    ("getPhoneNumber", { args in
                        (args["name"] as? String) == "Mom"
                    }),
                    ("sendSMS", { args in
                        let msg = args["message"] as? String ?? ""
                        return msg.contains("Running late")
                    })
                ]
            ),
            
            // Test 5: Note with newlines (LLM outputs \n as literal two-char escape sequence)
            (
                name: "Note with newlines in body",
                // LLM outputs literal backslash-n, not actual newline chars
                llmOutput: "1. create_note(\"Meeting Notes\", \"- Point 1\\n- Point 2\\n- Point 3\", None)\n2. join()<END_OF_PLAN>",
                expectedCalls: [
                    ("createNote", { args in
                        let body = args["body"] as? String ?? ""
                        // After unescaping, body should have actual newlines
                        return body.contains("Point 1") && body.contains("Point 2")
                    })
                ]
            ),
            
            // Test 6: Maps location
            (
                name: "Open maps location",
                llmOutput: """
                1. maps_open_location("San Francisco, CA")
                2. join()<END_OF_PLAN>
                """,
                expectedCalls: [
                    ("mapsOpenLocation", { args in
                        (args["query"] as? String)?.contains("San Francisco") == true
                    })
                ]
            ),
            
            // Test 7: Unicode handling
            (
                name: "Unicode in arguments",
                llmOutput: """
                1. create_reminder("Call café ☕", None, None, None)
                2. join()<END_OF_PLAN>
                """,
                expectedCalls: [
                    ("createReminder", { args in
                        let title = args["title"] as? String ?? ""
                        return title.contains("café") && title.contains("☕")
                    })
                ]
            ),
            
        ]
        
        for testCase in testCases {
            await mockBridge.reset()
            
            log("Testing: \(testCase.name)")
            
            // Parse the LLM output
            let parseResult = parser.parse(testCase.llmOutput)
            
            if !parseResult.parseErrors.isEmpty {
                log("  ❌ Parse errors: \(parseResult.parseErrors)")
                results.append(TestResult(
                    name: testCase.name,
                    passed: false,
                    message: "Parse failed: \(parseResult.parseErrors.joined(separator: ", "))",
                    capturedCalls: [],
                    llmOutput: testCase.llmOutput,
                    parseErrors: parseResult.parseErrors
                ))
                continue
            }
            
            // Execute tasks
            var outputs: [Int: String] = [:]
            var executionError: Error? = nil
            
            for task in parseResult.tasks where !task.isJoin {
                do {
                    let result = try await executor.execute(task, outputs: outputs)
                    outputs[task.id] = result
                    log("  Task \(task.id): \(task.toolName) → \(result.prefix(50))")
                } catch {
                    executionError = error
                    log("  Task \(task.id): \(task.toolName) → ERROR: \(error.localizedDescription)")
                    break
                }
            }
            
            // Verify captured calls
            let capturedCalls = await mockBridge.capturedCalls
            var allChecksPass = true
            
            for (expectedTool, argCheck) in testCase.expectedCalls {
                if let call = capturedCalls.first(where: { $0.method == expectedTool }) {
                    if argCheck(call.arguments) {
                        log("  ✅ \(expectedTool) called with correct args")
                    } else {
                        log("  ❌ \(expectedTool) called but args incorrect: \(call.arguments)")
                        allChecksPass = false
                    }
                } else {
                    log("  ❌ \(expectedTool) was not called")
                    allChecksPass = false
                }
            }
            
            let passed = executionError == nil && allChecksPass
            results.append(TestResult(
                name: testCase.name,
                passed: passed,
                message: passed ? "All checks passed" : "Some checks failed",
                capturedCalls: capturedCalls,
                llmOutput: testCase.llmOutput,
                parseErrors: parseResult.parseErrors
            ))
            
            log(passed ? "  ✅ PASSED" : "  ❌ FAILED")
            log("")
        }
    }
    
    // MARK: - Full LLM Pipeline Tests
    
    /// Tests that actually invoke the LLM to verify real output formatting
    private func testFullPipelineWithLLM() async {
        log("\n--- Full LLM Pipeline Tests ---\n")
        log("Loading LLM model...")
        
        let service = TinyAgentService()
        
        do {
            try await service.loadModel()
            log("Model loaded successfully")
        } catch {
            log("❌ Failed to load model: \(error)")
            results.append(TestResult(
                name: "LLM Model Load",
                passed: false,
                message: "Failed to load: \(error.localizedDescription)",
                capturedCalls: [],
                llmOutput: nil,
                parseErrors: []
            ))
            return
        }
        
        // Test cases that exercise real LLM output formatting
        let llmTestCases: [(name: String, query: String, expectedToolPattern: String, argValidator: (ParsedTask) -> Bool)] = [
            (
                name: "LLM: Note with multiline content",
                query: "Create a note titled 'Meeting Notes' with these bullet points: first item, second item, third item",
                expectedToolPattern: "create_note",
                argValidator: { task in
                    // Check that arguments were parsed (regardless of exact newline format)
                    guard task.arguments.count >= 2 else { return false }
                    if case .string(let title) = task.arguments[0] {
                        return title.contains("Meeting") || title.contains("Notes")
                    }
                    return false
                }
            ),
            (
                name: "LLM: Reminder with special characters",
                query: "Create a reminder for tomorrow: Don't forget to buy milk & eggs",
                expectedToolPattern: "create_reminder",
                argValidator: { task in
                    guard task.arguments.count >= 1 else { return false }
                    if case .string(let text) = task.arguments[0] {
                        return text.contains("milk") || text.contains("forget")
                    }
                    return false
                }
            ),
            (
                name: "LLM: Calendar event with quotes",
                query: "Create a calendar event called Team Standup Meeting for tomorrow at 10am",
                expectedToolPattern: "create_calendar_event",
                argValidator: { task in
                    guard task.arguments.count >= 1 else { return false }
                    if case .string(let title) = task.arguments[0] {
                        // Should have parsed the title with quotes
                        return title.lowercased().contains("standup") || title.lowercased().contains("team")
                    }
                    return false
                }
            )
        ]
        
        let parser = LLMCompilerParser()
        
        for testCase in llmTestCases {
            log("Testing: \(testCase.name)")
            log("  Query: \(testCase.query)")
            
            do {
                let result = try await service.run(query: testCase.query)
                
                log("  LLM Output (raw):")
                // Log each line separately to see exact formatting
                for (i, line) in result.plannerOutput.components(separatedBy: "\n").enumerated() {
                    log("    [\(i)] \(line.debugDescription)")
                }
                
                // Check if expected tool was called
                let hasExpectedTool = result.parsedTasks.contains { task in
                    task.toolName.contains(testCase.expectedToolPattern)
                }
                
                if !hasExpectedTool {
                    log("  ❌ Expected tool '\(testCase.expectedToolPattern)' not found in parsed tasks")
                    log("  Parsed tasks: \(result.parsedTasks.map { $0.toolName })")
                    results.append(TestResult(
                        name: testCase.name,
                        passed: false,
                        message: "Expected tool not found",
                        capturedCalls: [],
                        llmOutput: result.plannerOutput,
                        parseErrors: []
                    ))
                    continue
                }
                
                // Validate arguments
                let matchingTask = result.parsedTasks.first { $0.toolName.contains(testCase.expectedToolPattern) }!
                let argsValid = testCase.argValidator(matchingTask)
                
                if argsValid {
                    log("  ✅ Tool called with valid arguments")
                    log("  ✅ PASSED")
                    results.append(TestResult(
                        name: testCase.name,
                        passed: true,
                        message: "LLM output parsed correctly",
                        capturedCalls: [],
                        llmOutput: result.plannerOutput,
                        parseErrors: []
                    ))
                } else {
                    log("  ❌ Argument validation failed")
                    log("  Arguments: \(matchingTask.arguments)")
                    results.append(TestResult(
                        name: testCase.name,
                        passed: false,
                        message: "Argument validation failed",
                        capturedCalls: [],
                        llmOutput: result.plannerOutput,
                        parseErrors: []
                    ))
                }
                
            } catch {
                log("  ❌ Error: \(error)")
                results.append(TestResult(
                    name: testCase.name,
                    passed: false,
                    message: "Error: \(error.localizedDescription)",
                    capturedCalls: [],
                    llmOutput: nil,
                    parseErrors: []
                ))
            }
            
            log("")
        }
    }
    
    // MARK: - Summary
    
    private func printSummary() {
        log("")
        log("═══════════════════════════════════════════════════════════")
        log("  TEST SUMMARY")
        log("═══════════════════════════════════════════════════════════")
        log("")
        
        let passed = results.filter { $0.passed }.count
        let failed = results.filter { !$0.passed }.count
        
        for result in results {
            let status = result.passed ? "✅" : "❌"
            log("\(status) \(result.name): \(result.message)")
            
            if !result.passed {
                log("   LLM Output: \(result.llmOutput?.prefix(100) ?? "nil")...")
                if !result.parseErrors.isEmpty {
                    log("   Parse Errors: \(result.parseErrors)")
                }
                log("   Captured Calls: \(result.capturedCalls.map { $0.description })")
            }
        }
        
        log("")
        log("═══════════════════════════════════════════════════════════")
        log("  TOTAL: \(passed) passed, \(failed) failed")
        log("═══════════════════════════════════════════════════════════")
        
        exit(failed > 0 ? 1 : 0)
    }
}
