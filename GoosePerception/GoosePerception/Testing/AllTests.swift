//
// AllTests.swift
//
// Unified test runner for GoosePerception.
// Orchestrates all test suites without duplicating test logic.
//
// Usage:
//   GoosePerception --test                    # Run all fast tests (unit + integration)
//   GoosePerception --test --full             # Run all tests including LLM
//   GoosePerception --test --e2e              # Include end-to-end tests
//

import Foundation

/// Unified test runner - orchestrates existing test classes
@MainActor
class AllTests {
    
    struct Config {
        var runUnit = true
        var runIntegration = true
        var runE2E = false
        var runLLM = false
        var verbose = false
        
        static func parse(_ args: [String]) -> Config {
            var config = Config()
            
            // Check for specific suite flags
            let hasSpecific = args.contains("--unit") || args.contains("--integration") || 
                             args.contains("--e2e") || args.contains("--llm")
            
            if hasSpecific {
                config.runUnit = args.contains("--unit")
                config.runIntegration = args.contains("--integration")
                config.runE2E = args.contains("--e2e")
                config.runLLM = args.contains("--llm")
            }
            
            // --full enables everything
            if args.contains("--full") {
                config.runUnit = true
                config.runIntegration = true
                config.runE2E = true
                config.runLLM = true
            }
            
            config.verbose = args.contains("--verbose") || args.contains("-v")
            
            return config
        }
    }
    
    private let config: Config
    private let startTime = Date()
    
    init(config: Config) {
        self.config = config
    }
    
    // MARK: - Logging
    
    private func log(_ message: String) {
        print("[AllTests] \(message)")
        fflush(stdout)
    }
    
    private func header(_ title: String) {
        print("")
        print("═══════════════════════════════════════════════════════════")
        print("  \(title)")
        print("═══════════════════════════════════════════════════════════")
        print("")
        fflush(stdout)
    }
    
    // MARK: - Main Entry Point
    
    static func run() async {
        let config = Config.parse(CommandLine.arguments)
        let runner = AllTests(config: config)
        await runner.runAll()
    }
    
    func runAll() async {
        header("GOOSE PERCEPTION TEST SUITE")
        
        var suites: [String] = []
        if config.runUnit { suites.append("unit") }
        if config.runIntegration { suites.append("integration") }
        if config.runE2E { suites.append("e2e") }
        if config.runLLM { suites.append("llm") }
        
        log("Configuration:")
        log("  Suites: \(suites.joined(separator: ", "))")
        log("  Verbose: \(config.verbose)")
        log("")
        
        var totalPassed = 0
        var totalFailed = 0
        
        // Unit Tests - parser tests via TinyAgentIntegrationTests
        if config.runUnit {
            header("UNIT TESTS")
            log("Running parser unit tests...")
            
            // Quick parser tests
            let parser = LLMCompilerParser()
            var passed = 0
            var failed = 0
            
            // Test 1: Basic parsing
            let r1 = parser.parse("1. get_phone_number(\"John\")\n2. join()<END_OF_PLAN>")
            if r1.tasks.count == 2 && r1.tasks[0].toolName == "get_phone_number" {
                log("  ✅ Parser: Basic action")
                passed += 1
            } else {
                log("  ❌ Parser: Basic action")
                failed += 1
            }
            
            // Test 2: Multiple arguments
            let r2 = parser.parse("1. create_reminder(\"Buy milk\", \"2024-01-30\", None, None)\n2. join()<END_OF_PLAN>")
            if r2.tasks.count == 2 && r2.tasks[0].arguments.count == 4 {
                log("  ✅ Parser: Multiple arguments")
                passed += 1
            } else {
                log("  ❌ Parser: Multiple arguments")
                failed += 1
            }
            
            // Test 3: Task references
            let r3 = parser.parse("1. get_phone_number(\"John\")\n2. send_sms($1, \"Hi\")\n3. join()<END_OF_PLAN>")
            if r3.tasks.count == 3 {
                if case .reference(let ref) = r3.tasks[1].arguments[0], ref == 1 {
                    log("  ✅ Parser: Task references")
                    passed += 1
                } else {
                    log("  ❌ Parser: Task references (wrong ref)")
                    failed += 1
                }
            } else {
                log("  ❌ Parser: Task references")
                failed += 1
            }
            
            // Test 4: Unicode
            let r4 = parser.parse("1. create_reminder(\"Call café ☕\", None, None, None)\n2. join()<END_OF_PLAN>")
            if r4.tasks.count == 2, case .string(let title) = r4.tasks[0].arguments[0],
               title.contains("café") && title.contains("☕") {
                log("  ✅ Parser: Unicode support")
                passed += 1
            } else {
                log("  ❌ Parser: Unicode support")
                failed += 1
            }
            
            // Test 5: Newlines in strings (escaped as \\n)
            let r5 = parser.parse("1. create_note(\"Title\", \"Line1\\nLine2\")\n2. join()<END_OF_PLAN>")
            if r5.tasks.count == 2 && r5.parseErrors.isEmpty {
                log("  ✅ Parser: Escaped newlines")
                passed += 1
            } else {
                log("  ❌ Parser: Escaped newlines")
                failed += 1
            }
            
            log("")
            log("Unit tests: \(passed) passed, \(failed) failed")
            totalPassed += passed
            totalFailed += failed
        }
        
        // Integration Tests - mock execution tests
        if config.runIntegration {
            header("INTEGRATION TESTS")
            log("Running TinyAgent integration tests (mock execution)...")
            log("")
            
            let tester = TinyAgentIntegrationTests()
            tester.includeLLMTests = false
            await tester.runAllTests()
            
            // TinyAgentIntegrationTests prints its own results
            // We just note it ran
            log("")
            log("(Integration test results shown above)")
        }
        
        // E2E Tests - database and full pipeline
        if config.runE2E {
            header("END-TO-END TESTS")
            log("Running database and pipeline tests...")
            
            var passed = 0
            var failed = 0
            
            // Database test
            do {
                let db = Database.shared
                let testCapture = ScreenCapture(
                    timestamp: Date(),
                    focusedApp: "E2ETest",
                    focusedWindow: "Test Window",
                    ocrText: "E2E test \(UUID().uuidString)"
                )
                let id = try await db.insertScreenCapture(testCapture)
                if id > 0 {
                    log("  ✅ Database: Insert screen capture (ID=\(id))")
                    passed += 1
                } else {
                    log("  ❌ Database: Insert returned invalid ID")
                    failed += 1
                }
            } catch {
                log("  ❌ Database: \(error.localizedDescription)")
                failed += 1
            }
            
            log("")
            log("E2E tests: \(passed) passed, \(failed) failed")
            totalPassed += passed
            totalFailed += failed
        }
        
        // LLM Tests - requires model loading
        if config.runLLM {
            header("LLM TESTS (SLOW)")
            log("Running LLM integration tests with real model...")
            log("")
            
            // Use the static run method with LLM enabled
            await TinyAgentIntegrationTests.run(includeLLM: true)
            
            log("")
            log("(LLM test results shown above)")
        }
        
        // Summary
        let totalTime = Date().timeIntervalSince(startTime)
        header("TEST SUMMARY")
        
        log("Total: \(totalPassed) passed, \(totalFailed) failed")
        log("Time: \(String(format: "%.1f", totalTime))s")
        log("")
        
        // Note: Integration tests have their own exit, so we only exit if we didn't run them
        // or if we had unit/e2e failures
        if !config.runIntegration && !config.runLLM {
            exit(totalFailed > 0 ? 1 : 0)
        }
    }
}
