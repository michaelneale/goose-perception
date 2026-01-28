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
                
                var capture = ScreenCapture(
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
        // Test 6: LLM Analysis (Out-of-Process via perception-analyzer)
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 6: LLM Analysis (out-of-process)")
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
        // Test 7: Analysis Pipeline (Query existing data)
        // ═══════════════════════════════════════════════════════════════
        log("")
        log("▶ Test 7: Analysis Pipeline")
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
        // Test 8: Camera Permission Status
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
