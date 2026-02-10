import SwiftUI
import Foundation
import SwiftData

/// Voice capture UI component for recording and transcribing voice memos.
/// Designed for mechanics with large tap targets for gloved/greasy hands.
/// After transcription, identifies candidate tools, consumables, and chemicals
/// from the user's Garage inventory and shows a review screen.
struct VoiceCaptureView: View {
    @Environment(\.modelContext) private var viewContext
    @State private var voiceService = VoiceCaptureService()

    /// Callback with selected tool IDs, consumable IDs, chemical IDs, and transcribed text
    var onTranscriptionWithCandidates: ((Set<UUID>, Set<UUID>, Set<UUID>, String) -> Void)?

    /// Legacy callback for transcribed text only (backwards compatibility)
    var onTranscriptionComplete: ((String) -> Void)?

    /// Whether to show the dismiss button
    @Binding var isPresented: Bool

    /// Whether to show the candidate review sheet
    @State private var showingCandidateReview = false
    @State private var identifiedCandidates: [TranscriptionCandidate] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // MARK: - Permission Denied View
                // Feature #85: Handle microphone permission denial gracefully
                if !voiceService.microphonePermissionGranted || !voiceService.speechPermissionGranted {
                    permissionDeniedView
                } else {
                    // MARK: - Status Header
                    statusHeader

                    // MARK: - Audio Level Indicator
                    if voiceService.isRecording {
                        audioLevelIndicator
                    }

                    Spacer()

                    // MARK: - Transcription Display
                    transcriptionArea

                    Spacer()

                    // MARK: - Recording Controls
                    recordingControls

                    // MARK: - Error Display
                    if let error = voiceService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // MARK: - Action Buttons
                    if voiceService.transcriptionStatus == .completed && !voiceService.transcribedText.isEmpty {
                        actionButtons
                    }
                }
            }
            .padding()
            .navigationTitle("Voice Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        voiceService.cancelRecording()
                        isPresented = false
                    }
                }
            }
            .task {
                // Request permissions on appear
                if !voiceService.microphonePermissionGranted || !voiceService.speechPermissionGranted {
                    await voiceService.requestPermissions()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Re-check permissions when app returns from Settings
                voiceService.checkPermissions()
            }
            .sheet(isPresented: $showingCandidateReview) {
                CandidateReviewView(
                    transcribedText: voiceService.transcribedText,
                    candidates: identifiedCandidates,
                    onConfirm: { toolIDs, consumableIDs, chemicalIDs, text in
                        if let candidateCallback = onTranscriptionWithCandidates {
                            candidateCallback(toolIDs, consumableIDs, chemicalIDs, text)
                        } else {
                            onTranscriptionComplete?(text)
                        }
                        isPresented = false
                    },
                    isPresented: $showingCandidateReview
                )
                .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        VStack(spacing: 8) {
            // Status icon with loading indicator during transcription
            if voiceService.transcriptionStatus == .transcribing {
                // Show animated spinner during transcription
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.145, green: 0.388, blue: 0.922)))
                    .scaleEffect(2.0)
                    .frame(width: 40, height: 40)
                    .accessibilityIdentifier("transcriptionLoadingIndicator")
            } else {
                Image(systemName: statusIcon)
                    .font(.system(size: 40))
                    .foregroundColor(statusColor)
                    .symbolEffect(.pulse, isActive: voiceService.isRecording)
                    .accessibilityIdentifier("voiceStatusIcon")
            }

            // Status text
            Text(statusText)
                .font(.headline)
                .foregroundColor(.primary)
                .accessibilityIdentifier("voiceStatusText")

            // Duration
            if voiceService.isRecording || voiceService.recordingDuration > 0 {
                Text(voiceService.formattedDuration)
                    .font(.system(.title2, design: .monospaced))
                    .foregroundColor(voiceService.isRecording ? .red : .secondary)
                    .accessibilityIdentifier("voiceDuration")
            }
        }
    }

    private var statusIcon: String {
        switch voiceService.transcriptionStatus {
        case .idle: return "mic.circle"
        case .recording: return "mic.circle.fill"
        case .transcribing: return "text.bubble"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch voiceService.transcriptionStatus {
        case .idle: return .secondary
        case .recording: return .red
        case .transcribing: return Color(red: 0.145, green: 0.388, blue: 0.922)
        case .completed: return .green
        case .failed: return .red
        }
    }

    private var statusText: String {
        switch voiceService.transcriptionStatus {
        case .idle: return "Tap to Start Recording"
        case .recording: return "Recording... Speak Now"
        case .transcribing: return "Transcribing..."
        case .completed: return "Transcription Complete"
        case .failed: return "Transcription Failed"
        }
    }

    // MARK: - Audio Level Indicator

    private var audioLevelIndicator: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 8, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: voiceService.audioLevel)
            }
        }
        .frame(height: 40)
        .accessibilityIdentifier("audioLevelIndicator")
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Float(index) / 20.0
        if voiceService.audioLevel > threshold {
            if threshold > 0.7 { return .red }
            if threshold > 0.5 { return .orange }
            return .green
        }
        return Color.gray.opacity(0.3)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let threshold = Float(index) / 20.0
        if voiceService.audioLevel > threshold {
            return CGFloat(10.0 + Double(index) * 1.5)
        }
        return 10
    }

    // MARK: - Transcription Area

    private var transcriptionArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcription")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                // Show processing indicator in header during transcription
                if voiceService.transcriptionStatus == .transcribing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.7)
                        Text("Processing...")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    }
                    .accessibilityIdentifier("transcriptionProcessingIndicator")
                }
            }

            ZStack {
                ScrollView {
                    if voiceService.transcribedText.isEmpty {
                        if voiceService.isRecording {
                            Text("Listening... speak about the tools, consumables, and chemicals you used.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if voiceService.transcriptionStatus == .transcribing {
                            Text("Processing your speech...")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("Your transcribed text will appear here.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(voiceService.transcribedText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("transcribedText")
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Overlay loading indicator when transcribing with no text yet
                if voiceService.transcriptionStatus == .transcribing && voiceService.transcribedText.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.145, green: 0.388, blue: 0.922)))
                            .scaleEffect(1.5)
                        Text("Transcribing audio...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray6).opacity(0.9))
                    .cornerRadius(12)
                    .accessibilityIdentifier("transcriptionOverlayLoading")
                }
            }
        }
    }

    // MARK: - Recording Controls

    private var recordingControls: some View {
        HStack(spacing: 40) {
            if voiceService.isRecording {
                // Stop button - large target for gloved hands
                Button(action: {
                    voiceService.stopRecording()
                }) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 72, height: 72)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white)
                                .frame(width: 28, height: 28)
                        }

                        Text("Stop")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                }
                .accessibilityIdentifier("stopRecordingButton")
            } else {
                // Record button - large target for gloved hands
                Button(action: {
                    if voiceService.transcriptionStatus == .completed || voiceService.transcriptionStatus == .failed {
                        voiceService.reset()
                    }
                    voiceService.startRecording()
                }) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(voiceService.microphonePermissionGranted && voiceService.speechPermissionGranted
                                    ? Color.red : Color.gray)
                                .frame(width: 72, height: 72)

                            Circle()
                                .fill(Color.white)
                                .frame(width: 28, height: 28)
                        }

                        Text(voiceService.transcriptionStatus == .idle ? "Record" : "Re-record")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                }
                .disabled(!voiceService.microphonePermissionGranted || !voiceService.speechPermissionGranted)
                .accessibilityIdentifier("startRecordingButton")
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Use transcription button - now triggers candidate identification
            Button(action: {
                identifyCandidatesAndReview()
            }) {
                HStack {
                    Image(systemName: "text.badge.checkmark")
                    Text("Use Transcription")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0.145, green: 0.388, blue: 0.922))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .accessibilityIdentifier("useTranscriptionButton")

            // Discard button
            Button(action: {
                voiceService.reset()
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Discard & Re-record")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }
            .accessibilityIdentifier("discardTranscriptionButton")
        }
    }

    // MARK: - Permission Denied View

    /// Feature #85: Displays a helpful message when microphone/speech permission is denied
    /// and provides a button to open Settings so the user can enable the permission.
    private var permissionDeniedView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "mic.slash.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange
                .accessibilityHidden(true)

            // Title
            Text("Microphone Access Required")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("permissionDeniedTitle")

            // Explanation message
            VStack(spacing: 12) {
                if !voiceService.microphonePermissionGranted {
                    Text("Voice capture needs access to your microphone to record your task descriptions.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("microphonePermissionMessage")
                }

                if !voiceService.speechPermissionGranted {
                    Text("Speech recognition permission is needed to transcribe your voice recordings into text.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("speechPermissionMessage")
                }
            }
            .padding(.horizontal)

            Spacer()

            // Open Settings button - large tap target for gloved/greasy hands
            Button(action: openSettings) {
                HStack {
                    Image(systemName: "gear")
                        .font(.title3)
                    Text("Open Settings")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .accessibilityIdentifier("openSettingsButton")
            .accessibilityLabel("Open Settings")
            .accessibilityHint("Opens the Settings app to enable microphone permission")

            // Retry button to check permissions again
            Button(action: {
                Task {
                    await voiceService.requestPermissions()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Check Permissions Again")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }
            .accessibilityIdentifier("retryPermissionsButton")
            .accessibilityLabel("Check Permissions Again")
            .accessibilityHint("Requests microphone and speech permissions again")

            // Helpful note
            Text("After enabling permissions in Settings, return to this app to use voice capture.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .accessibilityIdentifier("permissionHelpNote")
        }
    }

    /// Opens the iOS Settings app to the app's settings page
    private func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }

    // MARK: - Candidate Identification

    /// Runs the TranscriptionCandidateService to find matching Garage items,
    /// then presents the CandidateReviewView for user confirmation.
    private func identifyCandidatesAndReview() {
        let candidateService = TranscriptionCandidateService()
        identifiedCandidates = candidateService.identifyCandidates(from: voiceService.transcribedText)

        print("VoiceCaptureView: Identified \(identifiedCandidates.count) candidates from transcription")

        // Show candidate review regardless of whether candidates were found
        // (review view handles the empty state gracefully)
        showingCandidateReview = true
    }
}

#Preview {
    VoiceCaptureView(
        onTranscriptionWithCandidates: { toolIDs, consumableIDs, chemicalIDs, text in
            print("Tools: \(toolIDs.count), Consumables: \(consumableIDs.count), Chemicals: \(chemicalIDs.count)")
            print("Text: \(text)")
        },
        isPresented: .constant(true)
    )
    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
}
