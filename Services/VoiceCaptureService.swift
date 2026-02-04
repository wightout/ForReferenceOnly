import Foundation
import AVFoundation
import Speech

/// VoiceCaptureService handles audio recording and on-device speech transcription
/// using Apple's Speech framework. Designed for mechanics to do voice brain-dumps
/// after completing maintenance tasks.
@MainActor
class VoiceCaptureService: NSObject, ObservableObject {

    // MARK: - Published State

    /// Current recording state
    @Published var isRecording = false

    /// Whether transcription is in progress
    @Published var isTranscribing = false

    /// The transcribed text result
    @Published var transcribedText: String = ""

    /// Current transcription status
    @Published var transcriptionStatus: TranscriptionStatus = .idle

    /// Error message if something goes wrong
    @Published var errorMessage: String?

    /// Audio level for visual feedback (0.0 to 1.0)
    @Published var audioLevel: Float = 0.0

    /// Recording duration in seconds
    @Published var recordingDuration: TimeInterval = 0

    // MARK: - Types

    enum TranscriptionStatus: String {
        case idle
        case recording
        case transcribing
        case completed
        case failed
    }

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?

    // MARK: - Permission Status

    /// Whether microphone permission has been granted
    @Published var microphonePermissionGranted = false

    /// Whether speech recognition permission has been granted
    @Published var speechPermissionGranted = false

    // MARK: - Initialization

    override init() {
        super.init()
        checkPermissions()
    }

    // MARK: - Permissions

    /// Check current permission status without prompting
    func checkPermissions() {
        // Check microphone
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphonePermissionGranted = true
        default:
            microphonePermissionGranted = false
        }

        // Check speech recognition
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechPermissionGranted = true
        default:
            speechPermissionGranted = false
        }
    }

    /// Request microphone and speech recognition permissions
    func requestPermissions() async {
        // Request microphone permission
        let micGranted = await AVAudioApplication.requestRecordPermission()
        microphonePermissionGranted = micGranted

        // Request speech recognition permission
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.speechPermissionGranted = (status == .authorized)
                    continuation.resume()
                }
            }
        }

        if !micGranted {
            errorMessage = "Microphone permission is required for voice capture."
        }
        if !speechPermissionGranted {
            errorMessage = "Speech recognition permission is required for transcription."
        }
    }

    // MARK: - Recording with Live Transcription

    /// Start recording audio with live speech-to-text transcription.
    /// Uses SFSpeechAudioBufferRecognitionRequest for real-time results.
    func startRecording() {
        // Reset state
        transcribedText = ""
        errorMessage = nil
        transcriptionStatus = .recording
        recordingDuration = 0
        recordingStartTime = Date()

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available on this device."
            transcriptionStatus = .failed
            return
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to configure audio session: \(error.localizedDescription)"
            transcriptionStatus = .failed
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Unable to create speech recognition request."
            transcriptionStatus = .failed
            return
        }

        // Enable partial results for live transcription
        recognitionRequest.shouldReportPartialResults = true

        // Use on-device recognition if available (iOS 13+)
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let result = result {
                    // Update transcribed text with best transcription
                    self.transcribedText = result.bestTranscription.formattedString

                    if result.isFinal {
                        self.transcriptionStatus = .completed
                        self.isTranscribing = false
                        print("VoiceCaptureService: Transcription completed - '\(self.transcribedText)'")
                    }
                }

                if let error = error {
                    // Don't treat cancellation as an error
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        // User cancelled or ended recognition - not a real error
                        if self.transcribedText.isEmpty {
                            self.transcriptionStatus = .completed
                        }
                    } else if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        // No speech detected
                        self.errorMessage = "No speech detected. Try speaking louder or closer to the microphone."
                        self.transcriptionStatus = .failed
                    } else {
                        self.errorMessage = "Transcription error: \(error.localizedDescription)"
                        self.transcriptionStatus = .failed
                    }
                    self.isTranscribing = false
                }
            }
        }

        // Set up audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            errorMessage = "Unable to create audio engine."
            transcriptionStatus = .failed
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap on input node to feed audio to recognizer
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Calculate audio level for visual feedback
            let channelData = buffer.floatChannelData?[0]
            let frames = buffer.frameLength
            if let channelData = channelData, frames > 0 {
                var sum: Float = 0
                for i in 0..<Int(frames) {
                    sum += abs(channelData[i])
                }
                let avgPower = sum / Float(frames)
                // Normalize to 0-1 range (typical speech is 0.01-0.1)
                let normalizedLevel = min(1.0, avgPower * 10.0)
                Task { @MainActor [weak self] in
                    self?.audioLevel = normalizedLevel
                }
            }
        }

        // Start the audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            isTranscribing = true

            // Start duration timer
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, let startTime = self.recordingStartTime else { return }
                    self.recordingDuration = Date().timeIntervalSince(startTime)
                }
            }

            print("VoiceCaptureService: Recording started with live transcription")
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            transcriptionStatus = .failed
            isRecording = false
            isTranscribing = false
        }
    }

    /// Stop recording and finalize transcription
    func stopRecording() {
        // Stop timer
        recordingTimer?.invalidate()
        recordingTimer = nil

        // Stop audio engine
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        // End recognition request
        recognitionRequest?.endAudio()

        isRecording = false
        audioLevel = 0

        // If we have text, mark as completed; if transcription is still running, mark as transcribing
        if !transcribedText.isEmpty {
            transcriptionStatus = .completed
            isTranscribing = false
        } else if transcriptionStatus == .recording {
            transcriptionStatus = .transcribing
        }

        // Reset audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("VoiceCaptureService: Failed to deactivate audio session: \(error)")
        }

        print("VoiceCaptureService: Recording stopped. Duration: \(String(format: "%.1f", recordingDuration))s")
    }

    /// Cancel the current recording and discard results
    func cancelRecording() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        stopRecording()

        transcribedText = ""
        transcriptionStatus = .idle
        errorMessage = nil

        print("VoiceCaptureService: Recording cancelled")
    }

    /// Reset the service to initial state
    func reset() {
        if isRecording {
            cancelRecording()
        }
        transcribedText = ""
        transcriptionStatus = .idle
        errorMessage = nil
        recordingDuration = 0
        audioLevel = 0
    }

    // MARK: - Formatting

    /// Format recording duration as MM:SS
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
