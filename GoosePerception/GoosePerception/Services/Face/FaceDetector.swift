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
        let rawMetrics: FaceMetrics?
    }

    struct EmotionResult {
        let emotion: String
        let confidence: Double
    }

    struct FaceMetrics {
        let mouthCurvature: Double
        let mouthAspectRatio: Double
        let eyeAspectRatio: Double
        let browHeight: Double
    }

    var calibrationData: FaceCalibrationData?
    
    /// Detect face and analyze emotion in an image
    func detectFace(in image: CGImage) async throws -> FaceDetection {
        // First detect face rectangles
        let faceRequest = VNDetectFaceRectanglesRequest()
        let landmarkRequest = VNDetectFaceLandmarksRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([faceRequest, landmarkRequest])

        guard let faceObservation = faceRequest.results?.first else {
            return FaceDetection(isPresent: false, userHash: nil, emotion: nil, boundingBox: nil, rawMetrics: nil)
        }

        // Get landmarks for emotion analysis
        var emotion: EmotionResult?
        var rawMetrics: FaceMetrics?

        if let landmarkObservation = landmarkRequest.results?.first,
           let landmarks = landmarkObservation.landmarks {
            let metrics = extractMetrics(from: landmarks)
            rawMetrics = metrics
            emotion = classifyEmotionWithCalibration(metrics: metrics)
        }

        // Generate anonymous hash from face bounding box (not truly identifying, just for session tracking)
        let userHash = generateUserHash(from: faceObservation.boundingBox)

        return FaceDetection(
            isPresent: true,
            userHash: userHash,
            emotion: emotion,
            boundingBox: faceObservation.boundingBox,
            rawMetrics: rawMetrics
        )
    }

    // MARK: - Metrics Extraction

    private func extractMetrics(from landmarks: VNFaceLandmarks2D) -> FaceMetrics {
        let mouthMetrics = analyzeMouth(landmarks)
        let eyeMetrics = analyzeEyes(landmarks)
        let browMetrics = analyzeBrows(landmarks)

        return FaceMetrics(
            mouthCurvature: mouthMetrics.curvature,
            mouthAspectRatio: mouthMetrics.aspectRatio,
            eyeAspectRatio: eyeMetrics.aspectRatio,
            browHeight: browMetrics.height
        )
    }

    // MARK: - Emotion Classification

    private func classifyEmotionWithCalibration(metrics: FaceMetrics) -> EmotionResult {
        if let calibration = calibrationData, calibration.isValid {
            // Use relative deviation from calibrated baseline
            let mouthDev = metrics.mouthCurvature - calibration.mouthCurvature
            let mouthARDev = metrics.mouthAspectRatio - calibration.mouthAspectRatio
            let eyeDev = metrics.eyeAspectRatio - calibration.eyeAspectRatio
            let browDev = metrics.browHeight - calibration.browHeight

            NSLog("🎭 Using CALIBRATED detection (baseline: mouth=%.2f, current=%.2f)",
                  calibration.mouthCurvature, metrics.mouthCurvature)

            return classifyEmotionRelative(
                mouthCurvatureDev: mouthDev,
                mouthAspectRatioDev: mouthARDev,
                eyeARDev: eyeDev,
                browHeightDev: browDev,
                absoluteEyeAR: metrics.eyeAspectRatio
            )
        } else {
            NSLog("🎭 Using UNCALIBRATED detection (no calibration data)")
            // Fall back to absolute thresholds
            return classifyEmotion(
                mouthCurvature: metrics.mouthCurvature,
                mouthAspectRatio: metrics.mouthAspectRatio,
                eyeAR: metrics.eyeAspectRatio,
                browHeight: metrics.browHeight
            )
        }
    }

    /// Classify emotion based on deviation from calibrated baseline
    private func classifyEmotionRelative(
        mouthCurvatureDev: Double,
        mouthAspectRatioDev: Double,
        eyeARDev: Double,
        browHeightDev: Double,
        absoluteEyeAR: Double
    ) -> EmotionResult {
        // Debug logging - crucial for tuning thresholds
        NSLog("🎭 Emotion deviations: mouth=%.3f, mouthAR=%.3f, eye=%.3f, brow=%.3f",
              mouthCurvatureDev, mouthAspectRatioDev, eyeARDev, browHeightDev)

        // Check neutral FIRST - if close to baseline, it's neutral
        // This prevents small fluctuations from triggering emotions
        let isNearNeutral = abs(mouthCurvatureDev) < 2.0 &&
                           abs(mouthAspectRatioDev) < 0.4 &&
                           abs(eyeARDev) < 0.06 &&
                           abs(browHeightDev) < 1.5

        if isNearNeutral {
            NSLog("🎭 -> NEUTRAL (in baseline zone)")
            return EmotionResult(emotion: "neutral", confidence: 0.75)
        }

        // Now check for positive emotions
        // When smiling:
        //   - mouth curvature becomes more POSITIVE (corners go up in Vision coords)
        //   - mouth gets wider (aspect ratio increases)

        // Happy: Clear smile - need BOTH wider mouth AND corners up
        if mouthAspectRatioDev > 0.5 && mouthCurvatureDev > 2.0 {
            let confidence = min(0.6 + mouthAspectRatioDev / 2.0, 0.95)
            NSLog("🎭 -> HAPPY (conf=%.2f)", confidence)
            return EmotionResult(emotion: "happy", confidence: confidence)
        }

        // Content: Moderate smile - either significant width OR curvature
        if mouthAspectRatioDev > 0.5 || mouthCurvatureDev > 2.5 {
            NSLog("🎭 -> CONTENT")
            return EmotionResult(emotion: "content", confidence: 0.7)
        }

        // Surprised: eyes wider + brows raised (brows move up = negative browDev)
        if eyeARDev > 0.08 && browHeightDev < -1.5 {
            NSLog("🎭 -> SURPRISED")
            return EmotionResult(emotion: "surprised", confidence: 0.8)
        }

        // Sad: Frown - mouth curves down (NEGATIVE mouthCurvatureDev = corners drop)
        if mouthCurvatureDev < -2.0 {
            let confidence = min(0.5 + (-mouthCurvatureDev) / 4.0, 0.85)
            NSLog("🎭 -> SAD (conf=%.2f)", confidence)
            return EmotionResult(emotion: "sad", confidence: confidence)
        }

        // Angry: brows lowered (positive browDev), tense/narrow mouth
        if browHeightDev > 1.5 && mouthAspectRatioDev < -0.1 {
            NSLog("🎭 -> ANGRY")
            return EmotionResult(emotion: "angry", confidence: 0.7)
        }

        // Frustrated: furrowed brows + slight frown (negative curvature = corners down)
        if browHeightDev > 1.5 && mouthCurvatureDev < -1.5 {
            NSLog("🎭 -> FRUSTRATED")
            return EmotionResult(emotion: "frustrated", confidence: 0.65)
        }

        // Tired: eyes more closed than baseline
        if eyeARDev < -0.04 || absoluteEyeAR < 0.15 {
            NSLog("🎭 -> TIRED")
            return EmotionResult(emotion: "tired", confidence: 0.7)
        }

        // Serious: furrowed brows, neutral mouth
        if browHeightDev > 1.0 && abs(mouthCurvatureDev) < 1.0 && abs(mouthAspectRatioDev) < 0.2 {
            NSLog("🎭 -> SERIOUS")
            return EmotionResult(emotion: "serious", confidence: 0.6)
        }

        // Focused: mild concentration
        if browHeightDev > 0.5 && browHeightDev < 1.5 && abs(mouthCurvatureDev) < 0.8 {
            NSLog("🎭 -> FOCUSED")
            return EmotionResult(emotion: "focused", confidence: 0.6)
        }

        // Default to neutral if nothing else matches
        NSLog("🎭 -> NEUTRAL (default)")
        return EmotionResult(emotion: "neutral", confidence: 0.55)
    }

    // Legacy method for non-calibrated detection
    private func analyzeEmotion(from landmarks: VNFaceLandmarks2D) -> EmotionResult {
        let metrics = extractMetrics(from: landmarks)
        return classifyEmotion(
            mouthCurvature: metrics.mouthCurvature,
            mouthAspectRatio: metrics.mouthAspectRatio,
            eyeAR: metrics.eyeAspectRatio,
            browHeight: metrics.browHeight
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

/// Minimal smoothing - just prevents single-frame glitches
actor EmotionSmoother {
    private var currentEmotion: String = "neutral"
    private var pendingEmotion: String?

    func addDetection(_ emotion: String, confidence: Double) -> (emotion: String, confidence: Double) {
        // High confidence always wins immediately
        if confidence > 0.8 {
            currentEmotion = emotion
            pendingEmotion = nil
            return (emotion, confidence)
        }

        // If same as current, just return it
        if emotion == currentEmotion {
            pendingEmotion = nil
            return (emotion, confidence)
        }

        // Different emotion - need to see it twice to switch (prevents glitches)
        if emotion == pendingEmotion {
            // Seen twice, switch to it
            currentEmotion = emotion
            pendingEmotion = nil
            return (emotion, confidence)
        } else {
            // First time seeing this different emotion, mark as pending
            pendingEmotion = emotion
            // Return current emotion for now
            return (currentEmotion, confidence * 0.8)
        }
    }

    func reset() {
        currentEmotion = "neutral"
        pendingEmotion = nil
    }
}
