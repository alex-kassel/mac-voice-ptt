import Foundation
import AVFoundation

final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var currentFileURL: URL?
    private var startTime: Date?
    private(set) var lastDuration: TimeInterval = 0.0

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
        let baseName = "dictaphone_\(UUID().uuidString)"

        // 1. Primary: AAC 16kHz Mono 32kbps (ultra-lightweight payload, ~160KB for 40s of voice)
        let aacURL = tempDir.appendingPathComponent("\(baseName).m4a")
        let aacSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000
        ]

        do {
            let rec = try AVAudioRecorder(url: aacURL, settings: aacSettings)
            rec.delegate = self
            rec.prepareToRecord()
            if rec.record() {
                self.currentFileURL = aacURL
                self.recorder = rec
                self.startTime = Date()
                return true
            }
        } catch {
            Logger.log("[AudioRecorder] AAC initialization failed (%@), attempting WAV fallback...", error.localizedDescription)
        }

        // 2. Fallback: 16kHz 16-bit Mono Linear PCM WAV
        let wavURL = tempDir.appendingPathComponent("\(baseName).wav")
        let wavSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            let rec = try AVAudioRecorder(url: wavURL, settings: wavSettings)
            rec.delegate = self
            rec.prepareToRecord()
            if rec.record() {
                self.currentFileURL = wavURL
                self.recorder = rec
                self.startTime = Date()
                return true
            } else {
                cleanupCurrentFile()
                return false
            }
        } catch {
            Logger.log("[AudioRecorder] Error starting recorder: %@", error.localizedDescription)
            cleanupCurrentFile()
            return false
        }
    }

    func stop() -> URL? {
        guard let rec = recorder, rec.isRecording else {
            cleanupCurrentFile()
            return nil
        }

        // Brief tail buffer (120ms) so the final syllable isn't clipped upon releasing key
        Thread.sleep(forTimeInterval: 0.12)

        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0.0
        self.lastDuration = duration
        rec.stop()
        recorder = nil

        guard let url = currentFileURL else { return nil }

        // Discard recordings shorter than 0.25 seconds or smaller than 1KB
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if duration < 0.25 || fileSize < 1024 {
            Logger.log("[AudioRecorder] Discarding short recording (duration: %.2fs, size: %d bytes)", duration, fileSize)
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
