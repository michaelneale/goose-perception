//
// AppleScriptTests.swift
//
// Test harness for AppleScript automation.
// Tests both the escaping logic and the actual AppleScript execution.
//
// Usage:
//   GoosePerception --test-applescript [options]
//
// Options:
//   --dry-run           Test escaping/formatting without executing
//   --verbose           Show full AppleScript output
//   --app <name>        Test specific app (contacts, reminders, calendar, notes, mail)
//

import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: "com.goose.perception", category: "AppleScriptTests")

/// Test harness for AppleScript automation
@MainActor
class AppleScriptTests {
    
    struct Config {
        var dryRun = false
        var verbose = false
        var testApp: String? = nil
        
        static func parse(_ args: [String]) -> Config {
            var config = Config()
            var i = 0
            while i < args.count {
                switch args[i] {
                case "--dry-run":
                    config.dryRun = true
                case "--verbose":
                    config.verbose = true
                case "--app":
                    if i + 1 < args.count {
                        config.testApp = args[i + 1]
                        i += 1
                    }
                default:
                    break
                }
                i += 1
            }
            return config
        }
    }
    
    struct TestCase {
        let name: String
        let input: String
        let expectedEscaped: String
        let script: String?  // Optional: full script to test
    }
    
    struct TestResult {
        let name: String
        let passed: Bool
        let message: String
        let details: [String]
    }
    
    private var results: [TestResult] = []
    private let config: Config
    
    init(config: Config) {
        self.config = config
    }
    
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        NSLog("%@", logMessage)
        print(logMessage)
        fflush(stdout)
    }
    
    private func header(_ title: String) {
        log("")
        log("═══════════════════════════════════════════════════════════")
        log("  \(title)")
        log("═══════════════════════════════════════════════════════════")
    }
    
    // MARK: - Entry Point
    
    static func run() async {
        let config = Config.parse(CommandLine.arguments)
        let tests = AppleScriptTests(config: config)
        await tests.runAllTests()
    }
    
    func runAllTests() async {
        header("APPLESCRIPT AUTOMATION TESTS")
        log("")
        log("Configuration:")
        log("  Dry run: \(config.dryRun)")
        log("  Verbose: \(config.verbose)")
        if let app = config.testApp {
            log("  Test app: \(app)")
        }
        log("")
        
        // Test 1: Escaping logic
        await testEscaping()
        
        // Test 2: Date formatting
        await testDateFormatting()
        
        // Test 3: Parser argument handling
        await testParserArguments()
        
        // Test 4: AppleScript execution (if not dry-run)
        if !config.dryRun {
            await testAppleScriptExecution()
        }
        
        // Print summary
        printSummary()
    }
    
    // MARK: - Escaping Tests
    
    private func testEscaping() async {
        header("TEST: String Escaping")
        var details: [String] = []
        var allPassed = true
        
        let testCases: [(input: String, expected: String)] = [
            // Basic strings
            ("Hello World", "Hello World"),
            
            // Quotes - these need to be escaped for AppleScript
            ("Say \"Hello\"", "Say \\\"Hello\\\""),
            
            // Backslashes
            ("Path\\to\\file", "Path\\\\to\\\\file"),
            
            // Newlines
            ("Line1\nLine2", "Line1\\nLine2"),
            
            // Tabs
            ("Col1\tCol2", "Col1\\tCol2"),
            
            // Mixed special chars
            ("He said \"Hello\nWorld\"", "He said \\\"Hello\\nWorld\\\""),
            
            // Unicode (should pass through unchanged)
            ("Emoji: 😀", "Emoji: 😀"),
            
            // Apostrophes (common in names - no escaping needed in double-quoted strings)
            ("O'Brien", "O'Brien"),
            
            // Empty string
            ("", ""),
        ]
        
        for (input, expected) in testCases {
            let escaped = escapeForAppleScript(input)
            let passed = escaped == expected
            allPassed = allPassed && passed
            
            let status = passed ? "✅" : "❌"
            details.append("\(status) \"\(input)\" → \"\(escaped)\"")
            if !passed {
                details.append("   Expected: \"\(expected)\"")
            }
        }
        
        results.append(TestResult(
            name: "String Escaping",
            passed: allPassed,
            message: allPassed ? "All escape sequences correct" : "Some escape sequences failed",
            details: details
        ))
        
        log(allPassed ? "✅ Escaping tests PASSED" : "❌ Escaping tests FAILED")
    }
    
    // MARK: - Date Formatting Tests
    
    private func testDateFormatting() async {
        header("TEST: Date Formatting for AppleScript")
        var details: [String] = []
        var allPassed = true
        
        // Test 1: Seconds from now approach (used by createReminder)
        let futureDate = Date().addingTimeInterval(3600)  // 1 hour from now
        let secondsFromNow = Int(futureDate.timeIntervalSinceNow)
        
        let script1 = """
            set targetDate to (current date) + \(secondsFromNow)
            return targetDate as string
            """
        
        details.append("Testing seconds-from-now approach:")
        details.append("  Seconds: \(secondsFromNow)")
        
        if !config.dryRun {
            do {
                let result = try await executeScript(script1)
                details.append("  Result: \(result)")
                allPassed = !result.isEmpty
            } catch {
                details.append("  Error: \(error.localizedDescription)")
                allPassed = false
            }
        } else {
            details.append("  Script: \(script1)")
        }
        
        // Test 2: Date components approach (for calendar events)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: futureDate)
        
        let script2 = """
            set theDate to current date
            set year of theDate to \(components.year ?? 2025)
            set month of theDate to \(components.month ?? 1)
            set day of theDate to \(components.day ?? 1)
            set hours of theDate to \(components.hour ?? 0)
            set minutes of theDate to \(components.minute ?? 0)
            set seconds of theDate to 0
            return theDate as string
            """
        
        details.append("")
        details.append("Testing date components approach:")
        
        if !config.dryRun {
            do {
                let result = try await executeScript(script2)
                details.append("  Result: \(result)")
            } catch {
                details.append("  Error: \(error.localizedDescription)")
                allPassed = false
            }
        } else {
            details.append("  Script generated correctly")
        }
        
        results.append(TestResult(
            name: "Date Formatting",
            passed: allPassed,
            message: allPassed ? "Date formatting works" : "Date formatting has issues",
            details: details
        ))
        
        log(allPassed ? "✅ Date formatting tests PASSED" : "❌ Date formatting tests FAILED")
    }
    
    // MARK: - Parser Argument Tests
    
    private func testParserArguments() async {
        header("TEST: LLMCompiler Parser Arguments")
        var details: [String] = []
        var allPassed = true
        
        let parser = LLMCompilerParser()
        
        let testCases: [(plan: String, expectedTasks: Int, expectedToolName: String?)] = [
            // Simple string argument
            (
                "1. get_phone_number(\"John\")\n2. join()<END_OF_PLAN>",
                2, "get_phone_number"
            ),
            
            // Multiple arguments with None
            (
                "1. create_reminder(\"Test\", \"2025-01-30 09:00:00\", None, None)\n2. join()<END_OF_PLAN>",
                2, "create_reminder"
            ),
            
            // Reference argument
            (
                "1. get_phone_number(\"John\")\n2. send_sms([$1], \"Hello\")\n3. join()<END_OF_PLAN>",
                3, "get_phone_number"
            ),
            
            // Argument with escaped newline
            (
                "1. create_note(\"Meeting Notes\", \"- Item 1\\n- Item 2\", None)\n2. join()<END_OF_PLAN>",
                2, "create_note"
            ),
            
            // Empty arguments
            (
                "1. join()<END_OF_PLAN>",
                1, "join"
            ),
        ]
        
        for (plan, expectedTasks, expectedTool) in testCases {
            let result = parser.parse(plan)
            let passed = result.tasks.count == expectedTasks && 
                        (expectedTool == nil || result.tasks.first?.toolName == expectedTool)
            
            allPassed = allPassed && passed
            
            let status = passed ? "✅" : "❌"
            details.append("\(status) Tasks: \(result.tasks.count)/\(expectedTasks)")
            if !passed {
                details.append("   Errors: \(result.parseErrors.joined(separator: "; "))")
            }
            if config.verbose {
                for task in result.tasks {
                    details.append("   → \(task.id). \(task.toolName)(\(task.arguments.count) args)")
                }
            }
        }
        
        results.append(TestResult(
            name: "Parser Arguments",
            passed: allPassed,
            message: allPassed ? "Parser handles all argument types" : "Parser has issues",
            details: details
        ))
        
        log(allPassed ? "✅ Parser tests PASSED" : "❌ Parser tests FAILED")
    }
    
    // MARK: - AppleScript Execution Tests
    
    private func testAppleScriptExecution() async {
        header("TEST: AppleScript Execution")
        var details: [String] = []
        
        // Test each app based on config
        let apps = config.testApp.map { [$0] } ?? ["contacts", "reminders", "calendar", "notes"]
        
        for app in apps {
            details.append("")
            details.append("Testing \(app.capitalized):")
            
            let (passed, message) = await testApp(app)
            details.append("  \(passed ? "✅" : "❌") \(message)")
        }
        
        let allPassed = !details.contains { $0.contains("❌") }
        
        results.append(TestResult(
            name: "AppleScript Execution",
            passed: allPassed,
            message: allPassed ? "All app integrations working" : "Some apps failed",
            details: details
        ))
        
        log(allPassed ? "✅ AppleScript execution tests PASSED" : "❌ AppleScript execution tests FAILED")
    }
    
    private func testApp(_ app: String) async -> (Bool, String) {
        let script: String
        
        switch app.lowercased() {
        case "contacts":
            script = """
                tell application "Contacts"
                    set personCount to count of people
                    return personCount as string
                end tell
                """
        case "reminders":
            script = """
                tell application "Reminders"
                    set listNames to name of every list
                    return listNames as string
                end tell
                """
        case "calendar":
            script = """
                tell application "Calendar"
                    set calNames to name of every calendar
                    return calNames as string
                end tell
                """
        case "notes":
            script = """
                tell application "Notes"
                    set noteCount to count of notes
                    return noteCount as string
                end tell
                """
        case "mail":
            script = """
                tell application "Mail"
                    set accountNames to name of every account
                    return accountNames as string
                end tell
                """
        default:
            return (false, "Unknown app: \(app)")
        }
        
        do {
            let result = try await executeScript(script)
            return (true, "Got: \(result.prefix(50))")
        } catch {
            // Check if it's a permission error
            let errorStr = error.localizedDescription
            if errorStr.contains("not allowed") || errorStr.contains("denied") {
                return (false, "Permission denied - grant access in System Settings")
            }
            return (false, "Error: \(errorStr)")
        }
    }
    
    // MARK: - Helpers
    
    private func escapeForAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
    
    private func executeScript(_ script: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    
                    if process.terminationStatus != 0 {
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: NSError(
                            domain: "AppleScriptTests",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: errorMessage]
                        ))
                    } else {
                        let output = String(data: outputData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Summary
    
    private func printSummary() {
        header("APPLESCRIPT TEST SUMMARY")
        log("")
        
        let passed = results.filter { $0.passed }.count
        let failed = results.filter { !$0.passed }.count
        
        for result in results {
            let status = result.passed ? "✅" : "❌"
            log("\(status) \(result.name): \(result.message)")
            for detail in result.details {
                log("   \(detail)")
            }
        }
        
        log("")
        log("═══════════════════════════════════════════════════════════")
        log("  TOTAL: \(passed) passed, \(failed) failed")
        log("═══════════════════════════════════════════════════════════")
        log("")
        
        if failed > 0 {
            log("")
            log("TROUBLESHOOTING TIPS:")
            log("  1. Grant automation permissions in System Settings > Privacy & Security")
            log("  2. Run with --dry-run to test escaping without execution")
            log("  3. Run with --verbose for detailed output")
            log("  4. Run with --app <name> to test a specific app")
            log("")
        }
        
        exit(failed > 0 ? 1 : 0)
    }
}
