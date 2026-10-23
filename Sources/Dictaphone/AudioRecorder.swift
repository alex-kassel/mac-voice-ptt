import Foundation
import AVFoundation

final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var currentFileURL: URL?
    private var startTime: Date?

    var isRecording: Bool {
        return recorder?.isRecording ?? false
    }

    static func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    func start() -> Bool {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "dictaphone_\(UUID().uuidString).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)
        currentFileURL = fileURL

        // 16kHz 16-bit Mono Linear PCM WAV (whisper optimal format)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            let rec = try AVAudioRecorder(url: fileURL, settings: settings)
            rec.delegate = self
            if rec.record() {
                self.recorder = rec
                self.startTime = Date()
                return true
            } else {
                cleanupCurrentFile()
                return false
            }
        } catch {
            NSLog("[AudioRecorder] Error starting recorder: %@", error.localizedDescription)
            cleanupCurrentFile()
            return false
        }
    }

    func stop() -> URL? {
        guard let rec = recorder, rec.isRecording else {
            cleanupCurrentFile()
            return nil
        }

        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0.0
        rec.stop()
        recorder = nil

        guard let url = currentFileURL else { return nil }

        // Discard recordings shorter than 0.25 seconds or smaller than 2KB
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if duration < 0.25 || fileSize < 2048 {
            NSLog("[AudioRecorder] Discarding short/empty recording (duration: %.2fs, size: %d bytes)", duration, fileSize)
            cleanupCurrentFile()
            return nil
        }

        currentFileURL = nil
        return url
    }

    func cancel() {
        if let rec = recorder, rec.isRecording {
            rec.stop()
        }
        recorder = nil
        cleanupCurrentFile()
    }

    private func cleanupCurrentFile() {
        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
            currentFileURL = nil
        }
    }
}
