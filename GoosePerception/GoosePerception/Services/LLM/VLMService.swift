//
// VLMService.swift
//
// STUBBED: VLM is disabled in this version.
// The MLX-based VLM has the same autorelease pool conflicts as the LLM.
// When we need VLM, add it to the perception-analyzer helper.
//

import Foundation
import CoreGraphics

/// Service for running Vision-Language Model inference
/// 
/// STUBBED: Currently disabled to avoid MLX autorelease crashes.
/// VLM can be added to the perception-analyzer helper later if needed.
actor VLMService {
    
    private(set) var isLoaded = false
    private(set) var isGenerating = false
    
    /// Default VLM model
    static let defaultModel = "mlx-community/Qwen2-VL-2B-Instruct-4bit"
    
    // MARK: - Model Management (Stubs)
    
    func loadModel(modelId: String = defaultModel) async throws {
        print("👁️ VLM: Disabled (would load \(modelId))")
        // Don't actually load - just mark as "loaded" for compatibility
        isLoaded = true
    }
    
    func unloadModel() {
        isLoaded = false
        print("👁️ VLM: Unloaded (stub)")
    }
    
    // MARK: - Inference (Stubs)
    
    /// Describe screenshot - returns placeholder
    func describeScreenshot(_ image: CGImage, prompt: String? = nil) async throws -> String {
        // VLM is disabled - return empty string
        print("👁️ VLM: describeScreenshot called but VLM is disabled")
        return ""
    }
    
    /// Batch describe - returns empty results
    func batchDescribe(_ images: [CGImage]) async throws -> [String] {
        return images.map { _ in "" }
    }
    
    /// Ask about image - returns empty
    func askAboutImage(_ image: CGImage, question: String) async throws -> String {
        return ""
    }
}

// MARK: - Errors

enum VLMError: Error, LocalizedError {
    case modelNotLoaded
    case generationInProgress
    case imageProcessingFailed
    case disabled
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "VLM model not loaded."
        case .generationInProgress:
            return "Generation already in progress."
        case .imageProcessingFailed:
            return "Failed to process image."
        case .disabled:
            return "VLM is currently disabled to avoid crashes. Use OCR instead."
        }
    }
}

// MARK: - Batch Processing Manager (Stub)

/// Manages batched VLM processing - DISABLED
actor VLMBatchProcessor {
    private let vlmService: VLMService
    private let database: Database
    
    var batchInterval: TimeInterval = 120
    
    init(vlmService: VLMService, database: Database) {
        self.vlmService = vlmService
        self.database = database
    }
    
    func start() async {
        print("👁️ VLM batch processor: Disabled")
    }
    
    func stop() {
        print("👁️ VLM batch processor: Stopped (was disabled)")
    }
}

// MARK: - Image Utilities

extension VLMService {
    /// Prepare image - kept for compatibility
    static func prepareImage(_ image: CGImage, maxSize: Int = 1024) -> CGImage? {
        let width = image.width
        let height = image.height
        
        if width > maxSize || height > maxSize {
            let scale = CGFloat(maxSize) / CGFloat(max(width, height))
            let newWidth = Int(CGFloat(width) * scale)
            let newHeight = Int(CGFloat(height) * scale)
            
            guard let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }
            
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
            
            return context.makeImage()
        }
        
        return image
    }
}
