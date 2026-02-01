import Foundation
import Vision
import CoreGraphics

/// Extracts text from images using Vision framework OCR
struct OCRProcessor {
    /// Minimum confidence threshold for OCR results
    var confidenceThreshold: Float = 0.5
    
    /// Performs OCR on a CGImage and returns the extracted text
    func performOCR(on image: CGImage) async throws -> String {
        let results = try await performOCRWithDetails(on: image)
        return results.map { $0.text }.joined(separator: "\n")
    }
    
    /// Performs OCR and returns detailed results including confidence and bounding boxes
    func performOCRWithDetails(on image: CGImage) async throws -> [OCRResult] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let results = observations.compactMap { observation -> OCRResult? in
                    guard observation.confidence >= self.confidenceThreshold,
                          let candidate = observation.topCandidates(1).first else {
                        return nil
                    }
                    
                    return OCRResult(
                        text: candidate.string,
                        confidence: observation.confidence,
                        boundingBox: observation.boundingBox
                    )
                }
                
                continuation.resume(returning: results)
            }
            
            // Configure for best accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"] // Can be expanded
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Performs OCR on image data
    func performOCR(onData data: Data) async throws -> String {
        guard let image = createCGImage(from: data) else {
            throw OCRError.invalidImageData
        }
        return try await performOCR(on: image)
    }
    
    private func createCGImage(from data: Data) -> CGImage? {
        guard let dataProvider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                pngDataProviderSource: dataProvider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            // Try JPEG
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            return cgImage
        }
        return image
    }
}

// MARK: - OCR Result

struct OCRResult {
    let text: String
    let confidence: Float
    let boundingBox: CGRect // Normalized coordinates (0-1)
    
    /// Converts bounding box to screen coordinates
    func screenRect(for imageSize: CGSize) -> CGRect {
        CGRect(
            x: boundingBox.origin.x * imageSize.width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height, // Flip Y
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )
    }
}

// MARK: - Errors

enum OCRError: Error, LocalizedError {
    case invalidImageData
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Invalid image data for OCR processing"
        case .processingFailed(let reason):
            return "OCR processing failed: \(reason)"
        }
    }
}

// MARK: - Batch Processing

extension OCRProcessor {
    /// Process multiple images concurrently
    func batchOCR(images: [CGImage]) async throws -> [String] {
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    let text = try await self.performOCR(on: image)
                    return (index, text)
                }
            }
            
            var results = [String](repeating: "", count: images.count)
            for try await (index, text) in group {
                results[index] = text
            }
            return results
        }
    }
}
