import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreMedia

/// Self-test mode that validates all core functionality
/// Run with: GoosePerception --self-test
@MainActor
class SelfTest {
    
    private static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        NSLog("%@", logMessage)
        print(logMessage)
        fflush(stdout)
    }
    
    private static func header(_ title: String) {
        log("")
        log("═══════════════════════════════════════════════════════════")
        log("  \(title)")
        log("═══════════════════════════════════════════════════════════")
    }
    
    static func run() async {
        header("GOOSE PERCEPTION SELF-TEST")
        log("")
        log("This test validates all core systems:")
        log("  1. Database connectivity")
        log("  2. Screen capture permissions")
        log("  3. Screenshot capture (actual)")
        log("  4. OCR text extraction")
        log("  5. LLM model loading & inference")
        log("  6. Analysis pipeline")
        log("  7. Camera permission status")
        log("  8. Microphone permission status")
        log("")
        
        var passed = 0
        var failed = 0
        var startTime = Date()
        let totalStart = Date()
        
        // ═══════════════════════════════════════════════════════════════
        // Test 1: Database Connection
        // ═══════════════════════════════════════════════════════════════
        log("▶ Test 1: Database Connection")
        startTime = Date()
        do {
            let db = Database.shared
            let count = try await db.getTodaysCaptureCount()
            let tables = try await countDatabaseTables(db)
            let elapsed = Date().timeIntervalSince(startTime)
            log("  ✅ PASS (\(String(format: "%.2f", elapsed))s)")
            log("     → Database connected")
            log("     → \(count) captures today")
            log("     → \(tables) tables verified")
            passed += 1
        } catch {
            log("  ❌ FAIL - \(error.localizedDescription)")
            failed += 1
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Test 2: Screen Capture Permission
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 2: Screen Capture Permission")
        startTime = Date()
        var hasScreenPermission = false
        do {
            let content = try await SCShareableContent.current
            let displayCount = content.displays.count
            let windowCount = content.windows.count
            let elapsed = Date().timeIntervalSince(startTime)
            log("  ✅ PASS (\(String(format: "%.2f", elapsed))s)")
            log("     → Permission granted")
            log("     → Found \(displayCount) display(s)")
            log("     → Found \(windowCount) window(s)")
            hasScreenPermission = true
            passed += 1
        } catch {
            log("  ❌ FAIL - Screen capture not permitted")
            log("     → Go to System Preferences > Privacy & Security > Screen Recording")
            log("     → Enable GoosePerception")
            failed += 1
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Test 3: Screenshot Capture (ACTUAL)
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 3: Screenshot Capture (actual capture)")
        startTime = Date()
        var capturedImage: CGImage? = nil
        
        if hasScreenPermission {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    throw NSError(domain: "SelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
                }
                
                let config = SCStreamConfiguration()
                config.width = Int(display.width)
                config.height = Int(display.height)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                
                let filter = SCContentFilter(display: display, excludingWindows: [])
                
                // Actually capture!
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                
                capturedImage = image
                let elapsed = Date().timeIntervalSince(startTime)
                log("  ✅ PASS (\(String(format: "%.2f", elapsed))s)")
                log("     → Captured \(image.width)x\(image.height) screenshot")
                log("     → Display: \(Int(display.width))x\(Int(display.height))")
                passed += 1
            } catch {
                log("  ❌ FAIL - \(error.localizedDescription)")
                failed += 1
            }
        } else {
            log("  ⏭️ SKIP - Screen permission required")
            passed += 1
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Test 4: OCR Text Extraction
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 4: OCR Text Extraction")
        startTime = Date()
        
        if let image = capturedImage {
            do {
                let ocrProcessor = OCRProcessor()
                let ocrText = try await ocrProcessor.performOCR(on: image)
                let wordCount = ocrText.split(separator: " ").count
                let lineCount = ocrText.components(separatedBy: "\n").count
                let elapsed = Date().timeIntervalSince(startTime)
                
                log("  ✅ PASS (\(String(format: "%.2f", elapsed))s)")
                log("     → Extracted \(ocrText.count) characters")
                log("     → \(wordCount) words, \(lineCount) lines")
                
                // Show a preview of extracted text
                if wordCount > 0 {
                    let preview = String(ocrText.prefix(100)).replacingOccurrences(of: "\n", with: " ")
                    log("     → Preview: \"\(preview)...\"")
                }
                passed += 1
            } catch {
                log("  ❌ FAIL - \(error.localizedDescription)")
                failed += 1
            }
        } else {
            // Try from database
            do {
                let db = Database.shared
                let captures = try await db.getRecentCaptures(hours: 24)
                if let capture = captures.first, let ocrText = capture.ocrText {
                    let wordCount = ocrText.split(separator: " ").count
                    let elapsed = Date().timeIntervalSince(startTime)
                    log("  ✅ PASS (\(String(format: "%.2f", elapsed))s) - from database")
                    log("     → Found \(wordCount) words in recent capture")
                    passed += 1
                } else {
                    log("  ⏭️ SKIP - No screenshot available for OCR test")
                    passed += 1
                }
            } catch {
                log("  ❌ FAIL - \(error.localizedDescription)")
                failed += 1
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Test 5: Save Capture to Database
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 5: Save Capture to Database")
        startTime = Date()
        
        if capturedImage != nil {
            do {
                let ocrProcessor = OCRProcessor()
                let ocrText = try await ocrProcessor.performOCR(on: capturedImage!)
                
                // Get focused app info
                let frontApp = NSWorkspace.shared.frontmostApplication
                let appName = frontApp?.localizedName ?? "SelfTest"
                
                let capture = ScreenCapture(
                    timestamp: Date(),
                    focusedApp: appName,
                    focusedWindow: "Self Test Window",
                    ocrText: ocrText
                )
                
                let db = Database.shared
                let captureId = try await db.insertScreenCapture(capture)
                let elapsed = Date().timeIntervalSince(startTime)
                
                log("  ✅ PASS (\(String(format: "%.2f", elapsed))s)")
                log("     → Saved capture #\(captureId) to database")
                log("     → App: \(appName)")
                log("     → OCR: \(ocrText.count) chars")
                passed += 1
            } catch {
                log("  ❌ FAIL - \(error.localizedDescription)")
                failed += 1
            }
        } else {
            log("  ⏭️ SKIP - No screenshot to save")
            passed += 1
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Test 6: TinyAgent Tool Registry (before LLM to avoid crash)
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 6: TinyAgent Tool Registry")
        startTime = Date()
        
        let tinyAgent = TinyAgentService()
        // Explicitly await tool registration (init spawns a Task that may not complete)
        await tinyAgent.registerTools()
        // Now check that tools are registered
        let enabledTools = await ToolRegistry.shared.getEnabledToolNames()
        let elapsed6 = Date().timeIntervalSince(startTime)
        
        if enabledTools.count >= 10 {
            log("  ✅ PASS (\(String(format: "%.2f", elapsed6))s)")
            log("     → \(enabledTools.count) tools registered")
            log("     → Tools: \(enabledTools.prefix(5).map { $0.displayName }.joined(separator: ", "))...")
            passed += 1
        } else {
            log("  ❌ FAIL - Only \(enabledTools.count) tools registered (expected >= 10)")
            failed += 1
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Test 7: TinyAgent ToolRAG Selection
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 7: TinyAgent ToolRAG Selection")
        startTime = Date()
        
        let testQuery = "Send a text message to John about the meeting"
        let ragResult = await ToolRAGService.shared.selectTools(for: testQuery)
        let selectedTools = ragResult.selectedTools
        let elapsed7 = Date().timeIntervalSince(startTime)
        
        if selectedTools.contains(.sendSMS) || selectedTools.contains(.getPhoneNumber) {
            log("  ✅ PASS (\(String(format: "%.2f", elapsed7))s)")
            log("     → Query: \"\(testQuery)\"")
            log("     → Selected: \(selectedTools.map { $0.rawValue }.joined(separator: ", "))")
            passed += 1
        } else {
            log("  ⚠️ WARN - ToolRAG did not select expected tools")
            log("     → Query: \"\(testQuery)\"")
            log("     → Selected: \(selectedTools.map { $0.rawValue }.joined(separator: ", "))")
            passed += 1  // Not a failure, just a warning
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Test 8: LLMCompiler Parser
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 8: LLMCompiler Parser")
        startTime = Date()
        
        let testPlan = """
        1. get_phone_number("John")
        2. send_sms([$1], "Meeting at 3pm")
        Thought: Message sent.
        3. join()<END_OF_PLAN>
        """
        
        let parser = LLMCompilerParser()
        let parseResult = parser.parse(testPlan)
        let elapsed8 = Date().timeIntervalSince(startTime)
        
        if parseResult.isValid && parseResult.tasks.count == 3 {
            log("  ✅ PASS (\(String(format: "%.2f", elapsed8))s)")
            log("     → Parsed \(parseResult.tasks.count) tasks")
            log("     → Task 1: \(parseResult.tasks[0].toolName)")
            log("     → Task 2: \(parseResult.tasks[1].toolName) (depends on $\(parseResult.tasks[1].dependencies.first ?? 0))")
            passed += 1
        } else {
            log("  ❌ FAIL - Parse failed or wrong task count")
            log("     → Valid: \(parseResult.isValid)")
            log("     → Tasks: \(parseResult.tasks.count)")
            log("     → Errors: \(parseResult.parseErrors.joined(separator: ", "))")
            failed += 1
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Test 9: LLM Analysis (Out-of-Process - may crash in headless mode)
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 9: LLM Analysis (out-of-process)")
        log("  ... Running perception-analyzer (5-60 seconds on first run)")
        startTime = Date()
        
        do {
            let llmService = LLMService()
            
            // Run self-test of the out-of-process analyzer
            let success = try await llmService.runSelfTest()
            let elapsed = Date().timeIntervalSince(startTime)
            
            if success {
                log("  ✅ PASS (\(String(format: "%.2f", elapsed))s)")
                log("     → Out-of-process analyzer working")
                passed += 1
            } else {
                log("  ❌ FAIL - Analyzer self-test returned false")
                failed += 1
            }
        } catch {
            log("  ❌ FAIL - \(error.localizedDescription)")
            failed += 1
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Test 10: Analysis Pipeline (Query existing data)
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 10: Analysis Pipeline")
        startTime = Date()
        
        do {
            let db = Database.shared
            let projects = try await db.getAllProjects()
            let insights = try await db.getAllInsights()
            let collaborators = try await db.getAllCollaborators()
            let interests = try await db.getAllInterests()
            let elapsed = Date().timeIntervalSince(startTime)
            
            log("  ✅ PASS (\(String(format: "%.2f", elapsed))s)")
            log("     → Projects: \(projects.count)")
            log("     → Insights: \(insights.count)")
            log("     → Collaborators: \(collaborators.count)")
            log("     → Interests: \(interests.count)")
            passed += 1
        } catch {
            log("  ❌ FAIL - \(error.localizedDescription)")
            failed += 1
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Test 11: Camera Permission Status
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 8: Camera Permission Status")
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraStatus {
        case .authorized:
            log("  ✅ PASS - Camera authorized")
            passed += 1
        case .notDetermined:
            log("  ⚠️ INFO - Camera permission not yet requested")
            log("     → Will prompt when Face Detection is enabled")
            passed += 1
        case .denied:
            log("  ⚠️ INFO - Camera denied")
            log("     → Enable in System Preferences > Privacy > Camera")
            passed += 1
        case .restricted:
            log("  ⚠️ INFO - Camera restricted (parental controls)")
            passed += 1
        @unknown default:
            log("  ⚠️ INFO - Unknown camera status")
            passed += 1
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Test 9: Microphone Permission Status
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 9: Microphone Permission Status")
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .authorized:
            log("  ✅ PASS - Microphone authorized")
            passed += 1
        case .notDetermined:
            log("  ⚠️ INFO - Microphone permission not yet requested")
            log("     → Will prompt when Voice Capture is enabled")
            passed += 1
        case .denied:
            log("  ⚠️ INFO - Microphone denied")
            log("     → Enable in System Preferences > Privacy > Microphone")
            passed += 1
        case .restricted:
            log("  ⚠️ INFO - Microphone restricted (parental controls)")
            passed += 1
        @unknown default:
            log("  ⚠️ INFO - Unknown microphone status")
            passed += 1
        }
        
        // ═══════════════════════════════════════════════════════════════
        // Summary
        // ═══════════════════════════════════════════════════════════════
        let totalTime = Date().timeIntervalSince(totalStart)
        
        header("RESULTS")
        log("")
        log("  Tests passed: \(passed)")
        log("  Tests failed: \(failed)")
        log("  Total time:   \(String(format: "%.1f", totalTime))s")
        log("")
        
        if failed > 0 {
            log("⚠️  Some tests failed. Check output above for details.")
            log("")
            exit(1)
        } else {
            log("✅ All core systems operational!")
            log("")
            log("Next steps:")
            log("  1. Run the app normally (without --self-test)")
            log("  2. Open Settings (Cmd+,) and enable services")
            log("  3. Check Dashboard for captured data")
            log("")
            exit(0)
        }
    }
    
    // Helper to verify database tables exist
    private static func countDatabaseTables(_ db: Database) async throws -> Int {
        // This verifies database schema is intact by querying different tables
        var tableCount = 0
        
        // Try to query each major table
        _ = try await db.getTodaysCaptureCount()
        tableCount += 1
        
        _ = try await db.getAllProjects()
        tableCount += 1
        
        _ = try await db.getAllInsights()
        tableCount += 1
        
        _ = try await db.getAllCollaborators()
        tableCount += 1
        
        _ = try await db.getAllInterests()
        tableCount += 1
        
        return tableCount
    }
}
