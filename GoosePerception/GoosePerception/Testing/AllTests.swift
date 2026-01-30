//
// AllTests.swift
//
// Unified test runner for GoosePerception.
// Runs all tests: unit, integration, and LLM.
//
// Usage: GoosePerception --test
//

import Foundation

/// Unified test runner - runs everything
@MainActor
class AllTests {
    
    private let startTime = Date()
    
    private func log(_ message: String) {
        print("[Test] \(message)")
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
        let runner = AllTests()
        await runner.runAll()
    }
    
    func runAll() async {
        header("GOOSE PERCEPTION TEST SUITE")
        
        // Run refiner/formatting tests first (fast, no LLM needed)
        await RefinerTests.run()
        
        // Run TinyAgent tests with LLM enabled
        // This includes: unit tests (parser), integration tests (mock execution), and LLM tests
        await TinyAgentIntegrationTests.run(includeLLM: true)
        
        // TinyAgentIntegrationTests calls exit() when done
    }
}
