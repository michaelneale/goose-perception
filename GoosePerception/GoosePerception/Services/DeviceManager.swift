//
// DeviceManager.swift
//
// Manages audio and video device enumeration and selection
//

import Foundation
import AVFoundation

@MainActor
class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    @Published var audioInputDevices: [AVCaptureDevice] = []
    @Published var videoInputDevices: [AVCaptureDevice] = []

    @Published var selectedAudioDeviceID: String? {
        didSet {
            if let id = selectedAudioDeviceID {
                UserDefaults.standard.set(id, forKey: "selectedAudioDeviceID")
            }
        }
    }

    @Published var selectedVideoDeviceID: String? {
        didSet {
            if let id = selectedVideoDeviceID {
                UserDefaults.standard.set(id, forKey: "selectedVideoDeviceID")
            }
        }
    }

    private init() {
        selectedAudioDeviceID = UserDefaults.standard.string(forKey: "selectedAudioDeviceID")
        selectedVideoDeviceID = UserDefaults.standard.string(forKey: "selectedVideoDeviceID")
        refreshDevices()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(devicesChanged),
            name: NSNotification.Name.AVCaptureDeviceWasConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(devicesChanged),
            name: NSNotification.Name.AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }

    @objc private func devicesChanged(_ notification: Notification) {
        Task { @MainActor in
            refreshDevices()
        }
    }

    func refreshDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        audioInputDevices = discoverySession.devices

        let videoDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        videoInputDevices = videoDiscovery.devices

        if selectedAudioDeviceID == nil, let first = audioInputDevices.first {
            selectedAudioDeviceID = first.uniqueID
        }
        if selectedVideoDeviceID == nil, let first = videoInputDevices.first {
            selectedVideoDeviceID = first.uniqueID
        }

        NSLog("📱 Devices refreshed: %d audio, %d video", audioInputDevices.count, videoInputDevices.count)
    }

    var selectedAudioDevice: AVCaptureDevice? {
        guard let id = selectedAudioDeviceID else {
            return audioInputDevices.first
        }
        return audioInputDevices.first { $0.uniqueID == id } ?? audioInputDevices.first
    }

    var selectedVideoDevice: AVCaptureDevice? {
        guard let id = selectedVideoDeviceID else {
            return videoInputDevices.first
        }
        return videoInputDevices.first { $0.uniqueID == id } ?? videoInputDevices.first
    }
}
