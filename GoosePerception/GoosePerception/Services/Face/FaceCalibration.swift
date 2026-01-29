//
// FaceCalibration.swift
//
// Stores personalized face metrics baseline for accurate emotion detection
//

import Foundation

struct FaceCalibrationData: Codable {
    let mouthCurvature: Double
    let mouthAspectRatio: Double
    let eyeAspectRatio: Double
    let browHeight: Double
    let calibratedAt: Date
    let sampleCount: Int

    var isValid: Bool {
        sampleCount >= 5
    }

    var age: TimeInterval {
        Date().timeIntervalSince(calibratedAt)
    }

    static var empty: FaceCalibrationData {
        FaceCalibrationData(
            mouthCurvature: 0,
            mouthAspectRatio: 3.0,
            eyeAspectRatio: 0.25,
            browHeight: 0,
            calibratedAt: .distantPast,
            sampleCount: 0
        )
    }
}

@MainActor
class FaceCalibrationManager: ObservableObject {
    static let shared = FaceCalibrationManager()

    @Published var calibrationData: FaceCalibrationData?
    @Published var isCalibrating = false
    @Published var calibrationProgress: Double = 0
    @Published var calibrationStatus: String = ""

    private var calibrationSamples: [(mouth: Double, mouthAR: Double, eye: Double, brow: Double)] = []
    private let requiredSamples = 10
    private let calibrationKey = "faceCalibrationData"

    private init() {
        loadCalibration()
    }

    var isCalibrated: Bool {
        calibrationData?.isValid == true
    }

    var calibrationAge: String? {
        guard let data = calibrationData, data.isValid else { return nil }
        let age = data.age
        if age < 3600 {
            return "\(Int(age / 60))m ago"
        } else if age < 86400 {
            return "\(Int(age / 3600))h ago"
        } else {
            return "\(Int(age / 86400))d ago"
        }
    }

    func startCalibration() {
        isCalibrating = true
        calibrationProgress = 0
        calibrationSamples = []
        calibrationStatus = "Look at the camera with a neutral expression..."
    }

    func addCalibrationSample(mouthCurvature: Double, mouthAspectRatio: Double, eyeAspectRatio: Double, browHeight: Double) {
        guard isCalibrating else { return }

        calibrationSamples.append((mouthCurvature, mouthAspectRatio, eyeAspectRatio, browHeight))
        calibrationProgress = Double(calibrationSamples.count) / Double(requiredSamples)

        if calibrationSamples.count < requiredSamples {
            calibrationStatus = "Hold still... \(calibrationSamples.count)/\(requiredSamples)"
        } else {
            finishCalibration()
        }
    }

    private func finishCalibration() {
        guard calibrationSamples.count >= requiredSamples else { return }

        let avgMouth = calibrationSamples.map { $0.mouth }.reduce(0, +) / Double(calibrationSamples.count)
        let avgMouthAR = calibrationSamples.map { $0.mouthAR }.reduce(0, +) / Double(calibrationSamples.count)
        let avgEye = calibrationSamples.map { $0.eye }.reduce(0, +) / Double(calibrationSamples.count)
        let avgBrow = calibrationSamples.map { $0.brow }.reduce(0, +) / Double(calibrationSamples.count)

        calibrationData = FaceCalibrationData(
            mouthCurvature: avgMouth,
            mouthAspectRatio: avgMouthAR,
            eyeAspectRatio: avgEye,
            browHeight: avgBrow,
            calibratedAt: Date(),
            sampleCount: calibrationSamples.count
        )

        saveCalibration()

        isCalibrating = false
        calibrationProgress = 1.0
        calibrationStatus = "Calibration complete!"

        NSLog("✅ Face calibration complete: mouth=%.2f, mouthAR=%.2f, eye=%.2f, brow=%.2f",
              avgMouth, avgMouthAR, avgEye, avgBrow)

        // Notify to update face detector with new calibration
        NotificationCenter.default.post(name: .updateFaceCalibration, object: nil)
    }

    func cancelCalibration() {
        isCalibrating = false
        calibrationProgress = 0
        calibrationSamples = []
        calibrationStatus = ""
    }

    func clearCalibration() {
        calibrationData = nil
        UserDefaults.standard.removeObject(forKey: calibrationKey)
        calibrationStatus = "Calibration cleared"
    }

    private func saveCalibration() {
        guard let data = calibrationData else { return }
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: calibrationKey)
        }
    }

    private func loadCalibration() {
        if let data = UserDefaults.standard.data(forKey: calibrationKey),
           let decoded = try? JSONDecoder().decode(FaceCalibrationData.self, from: data) {
            calibrationData = decoded
            NSLog("📊 Loaded face calibration from %@", calibrationAge ?? "unknown")
        }
    }
}
