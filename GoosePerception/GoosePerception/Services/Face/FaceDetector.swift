import Foundation
import Vision
import CoreGraphics
import CryptoKit

/// Detects faces and analyzes emotions using Vision framework landmarks
struct FaceDetector {
    
    struct FaceDetection {
        let isPresent: Bool
        let userHash: String?
        let emotion: EmotionResult?
        let boundingBox: CGRect?
    }
    
    struct EmotionResult {
        let emotion: String
        let confidence: Double
    }
    
    /// Detect face and analyze emotion in an image
    func detectFace(in image: CGImage) async throws -> FaceDetection {
        // First detect face rectangles
        let faceRequest = VNDetectFaceRectanglesRequest()
        let landmarkRequest = VNDetectFaceLandmarksRequest()
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([faceRequest, landmarkRequest])
        
        guard let faceObservation = faceRequest.results?.first else {
            return FaceDetection(isPresent: false, userHash: nil, emotion: nil, boundingBox: nil)
        }
        
        // Get landmarks for emotion analysis
        let emotion: EmotionResult?
        if let landmarkObservation = landmarkRequest.results?.first,
           let landmarks = landmarkObservation.landmarks {
            emotion = analyzeEmotion(from: landmarks)
        } else {
            emotion = nil
        }
        
        // Generate anonymous hash from face bounding box (not truly identifying, just for session tracking)
        let userHash = generateUserHash(from: faceObservation.boundingBox)
        
        return FaceDetection(
            isPresent: true,
            userHash: userHash,
            emotion: emotion,
            boundingBox: faceObservation.boundingBox
        )
    }
    
    // MARK: - Emotion Analysis
    
    private func analyzeEmotion(from landmarks: VNFaceLandmarks2D) -> EmotionResult {
        // Extract key measurements
        let mouthMetrics = analyzeMouth(landmarks)
        let eyeMetrics = analyzeEyes(landmarks)
        let browMetrics = analyzeBrows(landmarks)
        
        // Classification based on geometric analysis
        return classifyEmotion(
            mouthCurvature: mouthMetrics.curvature,
            mouthAspectRatio: mouthMetrics.aspectRatio,
            eyeAR: eyeMetrics.aspectRatio,
            browHeight: browMetrics.height
        )
    }
    
    private struct MouthMetrics {
        let curvature: Double // Negative = smile, Positive = frown
        let aspectRatio: Double // Width / Height
    }
    
    private struct EyeMetrics {
        let aspectRatio: Double // Eye openness
    }
    
    private struct BrowMetrics {
        let height: Double // Relative to eyes
    }
    
    private func analyzeMouth(_ landmarks: VNFaceLandmarks2D) -> MouthMetrics {
        guard let outerLips = landmarks.outerLips?.normalizedPoints,
              outerLips.count >= 6 else {
            return MouthMetrics(curvature: 0, aspectRatio: 3.0)
        }
        
        // Get mouth corners and center points
        let leftCorner = outerLips[0]
        let rightCorner = outerLips[outerLips.count / 2]
        
        // Top and bottom center
        let topCenter = outerLips[outerLips.count / 4]
        let bottomCenter = outerLips[(outerLips.count * 3) / 4]
        
        // Calculate curvature: compare corner height to center height
        let cornerMidY = (leftCorner.y + rightCorner.y) / 2
        let centerY = (topCenter.y + bottomCenter.y) / 2
        let curvature = (cornerMidY - centerY) * 100 // Scale up for easier thresholds
        
        // Calculate aspect ratio
        let width = abs(rightCorner.x - leftCorner.x)
        let height = abs(topCenter.y - bottomCenter.y)
        let aspectRatio = height > 0.001 ? width / height : 3.0
        
        return MouthMetrics(curvature: curvature, aspectRatio: aspectRatio)
    }
    
    private func analyzeEyes(_ landmarks: VNFaceLandmarks2D) -> EyeMetrics {
        // Average eye aspect ratio
        var totalAR: Double = 0
        var count = 0
        
        if let leftEye = landmarks.leftEye?.normalizedPoints, leftEye.count >= 4 {
            let ar = calculateEyeAspectRatio(leftEye)
            totalAR += ar
            count += 1
        }
        
        if let rightEye = landmarks.rightEye?.normalizedPoints, rightEye.count >= 4 {
            let ar = calculateEyeAspectRatio(rightEye)
            totalAR += ar
            count += 1
        }
        
        let avgAR = count > 0 ? totalAR / Double(count) : 0.25
        return EyeMetrics(aspectRatio: avgAR)
    }
    
    private func calculateEyeAspectRatio(_ points: [CGPoint]) -> Double {
        // Eye Aspect Ratio (EAR) - standard formula
        // EAR = (|p2-p6| + |p3-p5|) / (2 * |p1-p4|)
        guard points.count >= 6 else { return 0.25 }
        
        let p1 = points[0] // Left corner
        let p2 = points[1]
        let p3 = points[2]
        let p4 = points[3] // Right corner
        let p5 = points[4]
        let p6 = points[5]
        
        let vertical1 = distance(p2, p6)
        let vertical2 = distance(p3, p5)
        let horizontal = distance(p1, p4)
        
        guard horizontal > 0.001 else { return 0.25 }
        return (vertical1 + vertical2) / (2.0 * horizontal)
    }
    
    private func analyzeBrows(_ landmarks: VNFaceLandmarks2D) -> BrowMetrics {
        var browHeight: Double = 0
        var count = 0
        
        // Compare brow position to eye position
        if let leftBrow = landmarks.leftEyebrow?.normalizedPoints,
           let leftEye = landmarks.leftEye?.normalizedPoints,
           !leftBrow.isEmpty, !leftEye.isEmpty {
            let browCenter = leftBrow.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let eyeCenter = leftEye.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let browY = browCenter.y / CGFloat(leftBrow.count)
            let eyeY = eyeCenter.y / CGFloat(leftEye.count)
            browHeight += Double(browY - eyeY) * 100
            count += 1
        }
        
        if let rightBrow = landmarks.rightEyebrow?.normalizedPoints,
           let rightEye = landmarks.rightEye?.normalizedPoints,
           !rightBrow.isEmpty, !rightEye.isEmpty {
            let browCenter = rightBrow.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let eyeCenter = rightEye.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let browY = browCenter.y / CGFloat(rightBrow.count)
            let eyeY = eyeCenter.y / CGFloat(rightEye.count)
            browHeight += Double(browY - eyeY) * 100
            count += 1
        }
        
        return BrowMetrics(height: count > 0 ? browHeight / Double(count) : 0)
    }
    
    private func classifyEmotion(
        mouthCurvature: Double,
        mouthAspectRatio: Double,
        eyeAR: Double,
        browHeight: Double
    ) -> EmotionResult {
        // Classification rules based on geometric analysis
        // Negative curvature = corners higher than center = smile
        
        if mouthCurvature < -2 && mouthAspectRatio > 3.5 && eyeAR > 0.25 {
            return EmotionResult(emotion: "happy", confidence: min(abs(mouthCurvature) / 5.0, 0.95))
        }
        
        if mouthCurvature < -0.5 && mouthAspectRatio > 3.0 {
            return EmotionResult(emotion: "content", confidence: 0.7)
        }
        
        if mouthCurvature > 1 || (mouthAspectRatio < 2.5 && eyeAR < 0.2) {
            return EmotionResult(emotion: "sad", confidence: min(mouthCurvature / 3.0, 0.85))
        }
        
        if eyeAR > 0.35 && browHeight < -3 && mouthAspectRatio > 4.0 {
            return EmotionResult(emotion: "surprised", confidence: 0.8)
        }
        
        if browHeight > 2 && mouthAspectRatio < 3.0 && eyeAR < 0.25 {
            return EmotionResult(emotion: "angry", confidence: 0.7)
        }
        
        // Frustrated: furrowed brows, tense mouth, moderately open eyes
        if browHeight > 1 && mouthCurvature > 0.5 && mouthAspectRatio < 3.5 && eyeAR > 0.2 && eyeAR < 0.3 {
            return EmotionResult(emotion: "frustrated", confidence: 0.65)
        }
        
        if eyeAR < 0.15 {
            return EmotionResult(emotion: "tired", confidence: 0.8)
        }
        
        if browHeight > 0.5 && abs(mouthCurvature) < 1 {
            return EmotionResult(emotion: "serious", confidence: 0.6)
        }
        
        // Focused: slightly furrowed brows, relaxed mouth, steady eyes
        if browHeight > 0.3 && browHeight < 1.5 && abs(mouthCurvature) < 0.5 && eyeAR > 0.2 && eyeAR < 0.3 {
            return EmotionResult(emotion: "focused", confidence: 0.6)
        }
        
        return EmotionResult(emotion: "neutral", confidence: 0.5)
    }
    
    // MARK: - Helpers
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> Double {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(Double(dx * dx + dy * dy))
    }
    
    private func generateUserHash(from boundingBox: CGRect) -> String {
        // Create a simple hash from face position/size (not truly identifying)
        let data = "\(Int(boundingBox.width * 1000))x\(Int(boundingBox.height * 1000))"
        let hash = SHA256.hash(data: Data(data.utf8))
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Temporal Smoothing

/// Smooths emotion detection over time to reduce noise
actor EmotionSmoother {
    private var recentDetections: [(emotion: String, confidence: Double, timestamp: Date)] = []
    private let windowSize = 5
    private let maxAge: TimeInterval = 10.0 // seconds
    
    func addDetection(_ emotion: String, confidence: Double) -> (emotion: String, confidence: Double) {
        let now = Date()
        
        // Add new detection
        recentDetections.append((emotion, confidence, now))
        
        // Remove old detections
        recentDetections = recentDetections.filter { now.timeIntervalSince($0.timestamp) < maxAge }
        
        // Keep only recent window
        if recentDetections.count > windowSize {
            recentDetections = Array(recentDetections.suffix(windowSize))
        }
        
        // If high confidence, return immediately
        if confidence > 0.8 {
            return (emotion, confidence)
        }
        
        // Otherwise, vote among recent detections
        var emotionCounts: [String: (count: Int, totalConfidence: Double)] = [:]
        for detection in recentDetections {
            let existing = emotionCounts[detection.emotion] ?? (0, 0)
            emotionCounts[detection.emotion] = (existing.count + 1, existing.totalConfidence + detection.confidence)
        }
        
        // Return most common emotion with averaged confidence
        if let (bestEmotion, stats) = emotionCounts.max(by: { $0.value.count < $1.value.count }) {
            let avgConfidence = stats.totalConfidence / Double(stats.count)
            return (bestEmotion, avgConfidence)
        }
        
        return (emotion, confidence)
    }
    
    func reset() {
        recentDetections = []
    }
}
