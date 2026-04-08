import Foundation
import Speech
import AVFoundation

/// iOS 原生语音识别器，免费、支持离线
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var isAvailable = false

    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let audioEngine = AVAudioEngine()

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        isAvailable = recognizer?.isAvailable ?? false
    }

    /// 请求语音识别和麦克风权限
    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        let audioStatus = await AVAudioApplication.requestRecordPermission()
        return audioStatus
    }

    /// 开始录音并转写
    func startRecording() throws {
        // 取消已有任务
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechRecognizerError.unavailable
        }

        request.shouldReportPartialResults = true
        // 优先使用设备端识别（无需网络）
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stopRecording()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        transcript = ""
    }

    /// 停止录音
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

/// 语音识别错误
enum SpeechRecognizerError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "语音识别不可用"
        }
    }
}
