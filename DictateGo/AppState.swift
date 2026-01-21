import AppKit
import AVFoundation
import CoreAudio
import Foundation
import SwiftUI
import ApplicationServices
import ServiceManagement

enum AppStatus: String {
    case idle = "Idle"
    case recording = "Recording"
    case transcribing = "Transcribing"
}

enum OnboardingStep: String, CaseIterable {
    case welcome
    case setup
    case complete
}

enum ActivationMode: String, CaseIterable, Identifiable {
    case hold = "Press and Hold"
    case toggle = "Toggle"

    var id: String { rawValue }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var status: AppStatus = .idle {
        didSet {
            if status != .idle {
                stopMicTest()
            }
        }
    }
    @Published var lastTranscript: String?
    @Published var errorMessage: String?
    @Published var hotkey: Hotkey = .default
    @Published var history: [HistoryItem] = []
    @Published var selectedModel: ParakeetModelOption = .tdtV3
    @Published var modelStatus: ModelStatus = .checking
    @Published var isTranscriptionWarm: Bool = false
    @Published var isTranscriptionWarming: Bool = false
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var inputDeviceName: String = "Unknown"
    @Published var defaultInputDeviceName: String = "System default"
    @Published var selectedInputDeviceUID: String = ""
    @Published var micLevel: Float = 0
    @Published var isMicTesting: Bool = false
    @Published var isHotkeyPressed: Bool = false
    @Published var lastHotkeyDetectedAt: Date?
    @Published var microphoneAuthorized: Bool = false
    @Published var accessibilityAuthorized: Bool = false
    @Published var playSounds: Bool = true {
        didSet { playSoundsRaw = playSounds }
    }
    @Published var pauseSystemAudio: Bool = false {
        didSet { pauseSystemAudioRaw = pauseSystemAudio }
    }
    @Published var openAtLogin: Bool = false {
        didSet {
            openAtLoginRaw = openAtLogin
            guard !isUpdatingLoginItem else { return }
            updateLoginItemSetting()
        }
    }
    @Published var showRecordingBar: Bool = true {
        didSet {
            showRecordingBarRaw = showRecordingBar
            updateOverlayVisibilityForSetting()
        }
    }
    @Published var showDockIcon: Bool = true {
        didSet { showDockIconRaw = showDockIcon }
    }
    @Published var onboardingDemoText: String = ""
    @Published var onboardingDemoFieldFocused: Bool = false
    @Published var diagnosticsEnabled: Bool = false
    @Published var eventLog: [EventLogEntry] = []
    @Published private(set) var isFirstLaunch: Bool = false
    @Published private(set) var accessibilityRequestAttempts: Int = 0
    @Published var onboardingStep: OnboardingStep = .welcome {
        didSet { onboardingStepRaw = onboardingStep.rawValue }
    }
    @Published var onboardingFinished: Bool = false {
        didSet { onboardingFinishedRaw = onboardingFinished }
    }
    @Published var onboardingPreviewMode: Bool = false
    @Published var activationMode: ActivationMode = .hold {
        didSet { activationModeRaw = activationMode.rawValue }
    }

    @AppStorage("hotkeyData") private var hotkeyData: Data?
    @AppStorage("saveHistory") var saveHistory: Bool = false
    @AppStorage("autoPaste") var autoPaste: Bool = true
    @AppStorage("playSounds") private var playSoundsRaw: Bool = true
    @AppStorage("pauseSystemAudio") private var pauseSystemAudioRaw: Bool = false
    @AppStorage("openAtLogin") private var openAtLoginRaw: Bool = false
    @AppStorage("showRecordingBar") private var showRecordingBarRaw: Bool = true
    @AppStorage("showDockIcon") private var showDockIconRaw: Bool = true
    @AppStorage("selectedModel") private var selectedModelRaw: String = ParakeetModelOption.tdtV3.rawValue
    @AppStorage("selectedInputDeviceUID") private var selectedInputDeviceUIDRaw: String = ""
    @AppStorage("historyItems") private var historyData: Data?
    @AppStorage("lastHotkeyDetectedAt") private var lastHotkeyDetectedAtRaw: Double = 0
    @AppStorage("onboardingStep") private var onboardingStepRaw: String = OnboardingStep.welcome.rawValue
    @AppStorage("onboardingFinished") private var onboardingFinishedRaw: Bool = false
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @AppStorage("activationMode") private var activationModeRaw: String = ActivationMode.hold.rawValue

    private let hotkeyMonitor = HotkeyMonitor()
    private let audioCapture = AudioCaptureManager()
    private let transcription = TranscriptionManager()
    private let pasteManager = PasteManager()
    private let overlayState = OverlayState()
    private lazy var overlayController = OverlayController(state: overlayState)
    private let audioLevelMonitor = AudioLevelMonitor()
    private var activationObserver: Any?
    private var permissionTimer: Timer?
    private var hotkeyRefreshTimer: Timer?
    private var recordingStartedAt: Date?
    private var maxRecordingLevel: Float = 0
    private var lastTranscriptAt: Date?
    private var overlayErrorToken: UUID?
    private var overlayToastToken: UUID?
    private var airPodsWarningSuppressedDeviceName: String?
    private lazy var startSound: NSSound? = {
        if let url = Bundle.main.url(
            forResource: "computer-mouse-click-02-383961",
            withExtension: "mp3",
            subdirectory: "Resources"
        ) {
            return NSSound(contentsOf: url, byReference: true)
        }
        return NSSound(contentsOfFile: "/System/Library/Sounds/Frog.aiff", byReference: true)
    }()
    private let soundVolume: Float = 0.3
    private var lastSpeechAt: Date?
    private var toggleMaxTimer: Timer?
    private var transcriptionWarmupTask: Task<Void, Never>?
    private var silenceStopTriggered = false
    private var pausedSystemAudioForRecording = false
    private var isRequestingMicAccess = false
    private var isUpdatingLoginItem = false
    private var isOnboardingDemoActive = false
    private var isDemoMicMonitoring = false

    private let minRecordingDuration: TimeInterval = 0.35
    private let minIgnoreDuration: TimeInterval = 0.1
    private let minRecordingLevel: Float = 0.08
    private let minErrorDuration: TimeInterval = 2.0
    private let duplicateSuppressionInterval: TimeInterval = 2.0
    private let toggleSilenceTimeout: TimeInterval = 5.0
    private let toggleMaxDuration: TimeInterval = 120.0
    private let toggleSilenceThreshold: Float = 0.15

    private init(preview: Bool) {
        let normalizedHistory = { [self] (items: [HistoryItem]) -> [HistoryItem] in
            items.compactMap { item in
                let normalizedText = normalizedHistoryText(item.text)
                guard !normalizedText.isEmpty else { return nil }
                if normalizedText == item.text {
                    return item
                }
                return HistoryItem(id: item.id, text: normalizedText, timestamp: item.timestamp)
            }
        }

        if let hotkeyData, let stored = try? JSONDecoder().decode(Hotkey.self, from: hotkeyData) {
            if stored == .legacyDefaultOptionSpace {
                hotkey = .default
                self.hotkeyData = try? JSONEncoder().encode(hotkey)
                logEvent("Migrated legacy default hotkey to Option.")
            } else {
                hotkey = stored
            }
        }

        if let historyData {
            if let stored = try? JSONDecoder().decode([HistoryItem].self, from: historyData) {
                let normalized = normalizedHistory(stored)
                history = normalized
                if normalized != stored {
                    self.historyData = try? JSONEncoder().encode(normalized)
                    logEvent("Normalized history entries.")
                }
            } else if let stored = try? JSONDecoder().decode([String].self, from: historyData) {
                let now = Date()
                let items = stored.enumerated().map { index, text in
                    HistoryItem(text: text, timestamp: now.addingTimeInterval(TimeInterval(-index * 60)))
                }
                let normalized = normalizedHistory(items)
                history = normalized
                self.historyData = try? JSONEncoder().encode(normalized)
                logEvent("Migrated legacy history entries.")
            }
        }

        selectedModel = .tdtV3
        if selectedModelRaw != ParakeetModelOption.tdtV3.rawValue {
            selectedModelRaw = ParakeetModelOption.tdtV3.rawValue
            logEvent("Model reset to Parakeet TDT v3.")
        }
        selectedInputDeviceUID = selectedInputDeviceUIDRaw
        playSounds = playSoundsRaw
        pauseSystemAudio = pauseSystemAudioRaw
        openAtLogin = openAtLoginRaw
        showRecordingBar = showRecordingBarRaw
        showDockIcon = showDockIconRaw
        onboardingStep = OnboardingStep(rawValue: onboardingStepRaw) ?? .welcome
        onboardingFinished = onboardingFinishedRaw
        activationMode = ActivationMode(rawValue: activationModeRaw) ?? .hold
        if lastHotkeyDetectedAtRaw > 0 {
            lastHotkeyDetectedAt = Date(timeIntervalSince1970: lastHotkeyDetectedAtRaw)
        }

        if preview {
            return
        }

        isFirstLaunch = !hasLaunchedBefore
        if !hasLaunchedBefore {
            hasLaunchedBefore = true
        }

        refreshPermissionStatus()

        if onboardingStep == .complete && !onboardingFinished {
            if isOnboardingComplete {
                onboardingFinished = true
            } else {
                onboardingStep = .setup
            }
        }

        if hotkey.modifierFlags.isEmpty {
            hotkey = .default
            hotkeyData = try? JSONEncoder().encode(hotkey)
            logEvent("Reset invalid hotkey to default.")
        }

        hotkeyMonitor.start(hotkey: hotkey, onPress: { [weak self] in
            self?.handleHotkeyPress()
        }, onRelease: { [weak self] in
            self?.handleHotkeyRelease()
        })
        scheduleHotkeyRefresh()

        overlayState.onDismiss = { [weak self] in
            self?.handleOverlayDismiss()
        }

        refreshInputDevices()
        refreshModelStatus()
        updateOnboardingProgress()
        updateLoginItemSetting()

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionStatus()
                self?.scheduleHotkeyRefresh()
            }
        }

    }

    private convenience init() {
        self.init(preview: false)
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func setHotkey(_ hotkey: Hotkey) {
        if hotkey.modifierFlags.isEmpty {
            errorMessage = "Hotkey must include at least one modifier."
            logEvent("Hotkey rejected: missing modifier.")
            return
        }
        self.hotkey = hotkey
        hotkeyMonitor.updateHotkey(hotkey)
        hotkeyData = try? JSONEncoder().encode(hotkey)
        logEvent("Hotkey set to \(hotkey.displayString).")
        updateOnboardingProgress()
    }

    func setSelectedModel(_ model: ParakeetModelOption) {
        selectedModel = model
        selectedModelRaw = model.rawValue
        refreshModelStatus()
    }

    func refreshModelStatus() {
        modelStatus = .checking
        Task { [weak self] in
            guard let self else { return }
            let available = await transcription.isModelAvailable(self.selectedModel)
            await MainActor.run {
                self.modelStatus = available ? .ready : .missing
                if available {
                    self.warmUpTranscriptionIfNeeded(context: "model-status")
                } else {
                    self.isTranscriptionWarm = false
                }
                self.updateOnboardingProgress()
            }
        }
    }

    func requestModelDownload() {
        modelStatus = .downloading
        errorMessage = nil
        logEvent("Model download started.")

        Task { [weak self] in
            guard let self else { return }
            do {
                try await transcription.downloadModel(self.selectedModel)
                try await transcription.loadModelIfNeeded(self.selectedModel)
                await MainActor.run {
                    self.modelStatus = .ready
                    self.isTranscriptionWarm = true
                    self.isTranscriptionWarming = false
                    self.logEvent("Model download completed.")
                    self.updateOnboardingProgress()
                }
            } catch {
                await MainActor.run {
                    self.modelStatus = .failed(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                    self.logEvent("Model download failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func startRecording() {
        guard status != .recording else { return }
        stopMicTest()
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .authorized:
            break
        case .notDetermined:
            requestMicrophoneAccessIfNeeded()
            logEvent("Microphone access requested from hotkey.")
            return
        case .denied, .restricted:
            errorMessage = "Microphone access denied."
            showOverlayError(
                title: "Microphone access required",
                subtitle: "Enable microphone access in System Settings."
            )
            return
        @unknown default:
            errorMessage = "Microphone access unavailable."
            showOverlayError(
                title: "Microphone access required",
                subtitle: "Enable microphone access in System Settings."
            )
            return
        }
        guard ensureInputDeviceAvailable(context: "recording") else { return }
        stopMicTest()
        warmUpTranscriptionIfNeeded(context: "recording-start")
        overlayErrorToken = nil
        let now = Date()
        lastHotkeyDetectedAt = now
        lastHotkeyDetectedAtRaw = now.timeIntervalSince1970
        errorMessage = nil
        let didPauseAudio = pauseSystemAudioIfNeeded()
        let selectedDeviceID = selectedInputDeviceID()
        let defaultDeviceID = AudioDeviceManager.defaultInputDeviceID()
        let selectedMatchesDefault = selectedDeviceID != nil && selectedDeviceID == defaultDeviceID
        do {
            try beginRecordingSession(deviceID: selectedDeviceID, showFallbackToast: false)
        } catch {
            if selectedDeviceID != nil {
                if selectedMatchesDefault {
                    logEvent("Selected mic failed to start; system default matches selection. Retrying with system default.")
                } else {
                    logEvent("Recording failed for selected mic: \(error.localizedDescription). Trying system default.")
                }
                do {
                    try beginRecordingSession(deviceID: nil, showFallbackToast: !selectedMatchesDefault)
                    if selectedMatchesDefault {
                        logEvent("System default matches selected mic; continuing without fallback toast.")
                    }
                    return
                } catch {
                    status = .idle
                    errorMessage = error.localizedDescription
                    logEvent("Recording failed: \(error.localizedDescription)")
                    showOverlayError(
                        title: "Microphone failed to start",
                        subtitle: error.localizedDescription
                    )
                    overlayController.hide()
                    if didPauseAudio {
                        resumeSystemAudioIfNeeded()
                    }
                }
            } else {
                status = .idle
                errorMessage = error.localizedDescription
                logEvent("Recording failed: \(error.localizedDescription)")
                showOverlayError(
                    title: "Microphone failed to start",
                    subtitle: error.localizedDescription
                )
                overlayController.hide()
                if didPauseAudio {
                    resumeSystemAudioIfNeeded()
                }
            }
        }
    }

    private func beginRecordingSession(deviceID: AudioDeviceID?, showFallbackToast: Bool) throws {
        try audioCapture.startRecording(deviceID: deviceID)
        status = .recording
        let modeLabel = deviceID == nil ? "system default mic" : "selected mic"
        logEvent("Recording started (\(modeLabel)).")
        playStartSound()
        overlayState.status = .recording
        overlayState.audioLevel = 0
        recordingStartedAt = Date()
        maxRecordingLevel = 0
        silenceStopTriggered = false
        lastSpeechAt = Date()
        if activationMode == .toggle {
            startToggleTimers()
        }
        showOverlayIfAllowed()
        if showFallbackToast {
            showOverlayToast(
                message: "Selected mic unavailable. Using system default.",
                duration: 3.0
            )
        }
        audioCapture.startMetering { [weak self] level in
            guard let self else { return }
            self.overlayState.audioLevel = level
            if level > self.maxRecordingLevel {
                self.maxRecordingLevel = level
            }
            let speakingThreshold: Float = 0.2
            self.overlayState.status = level > speakingThreshold ? .speaking : .recording
            self.handleToggleSilence(level: level)
        }
    }

    func stopRecording() {
        guard status == .recording else { return }
        defer { resumeSystemAudioIfNeeded() }
        stopToggleTimers()
        status = .transcribing
        logEvent("Recording stopped. Transcribing...")
        overlayState.status = .transcribing
        let duration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil
        let peakLevel = maxRecordingLevel
        maxRecordingLevel = 0
        guard let url = audioCapture.stopRecording() else {
            status = .idle
            overlayState.status = .hidden
            overlayController.hide()
            logEvent("Recording stop failed: no audio file created.")
            return
        }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        logEvent(String(format: "Recording stats: %.2fs, peak %.2f, %d bytes.", duration, peakLevel, fileSize))

        if duration < minIgnoreDuration {
            status = .idle
            overlayState.status = .hidden
            overlayController.hide()
            logEvent(String(format: "Recording ignored: too short (%.2fs).", duration))
            try? FileManager.default.removeItem(at: url)
            return
        }

        if duration < minRecordingDuration {
            status = .idle
            overlayState.status = .hidden
            overlayController.hide()
            logEvent(String(format: "Skipped transcription: recording too short (%.2fs).", duration))
            try? FileManager.default.removeItem(at: url)
            return
        }

        if peakLevel < minRecordingLevel {
            status = .idle
            overlayState.status = .hidden
            overlayController.hide()
            if duration >= minErrorDuration {
                showOverlayError(
                    title: "Is your microphone muted?",
                    subtitle: "We didn't pick up any audio from \(inputDeviceName)."
                )
                showOverlayToast(message: "No audio detected. Check your microphone and try again.", duration: 3.5)
                logEvent(String(format: "Skipped transcription: audio too quiet (peak %.2f).", peakLevel))
            } else {
                logEvent(String(format: "Recording ignored: audio too quiet (peak %.2f, %.2fs).", peakLevel, duration))
            }
            try? FileManager.default.removeItem(at: url)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await transcription.transcribe(audioURL: url, model: self.selectedModel)
                await MainActor.run {
                    self.handleTranscriptionSuccess(text)
                }
            } catch {
                await MainActor.run {
                    self.handleTranscriptionFailure(error)
                }
            }
        }
    }

    private func handleTranscriptionSuccess(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let previous = lastTranscript?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDuplicate = trimmed == previous
            && now.timeIntervalSince(lastTranscriptAt ?? .distantPast) < duplicateSuppressionInterval
        lastTranscript = text
        lastTranscriptAt = now
        status = .idle
        errorMessage = nil
        logEvent("Transcription completed (\(trimmed.count) chars).")
        if trimmed.isEmpty {
            logEvent("Auto-paste skipped: empty transcript.")
            overlayState.status = .hidden
            overlayController.hide()
            return
        }
        if isDuplicate {
            logEvent("Auto-paste skipped: duplicate transcript.")
            return
        }
        if isOnboardingDemoActive && onboardingDemoFieldFocused {
            if onboardingDemoText.isEmpty {
                onboardingDemoText = trimmed
            } else {
                onboardingDemoText += (onboardingDemoText.hasSuffix(" ") ? "" : " ") + trimmed
            }
            logEvent("Onboarding demo text updated.")
            overlayState.status = .hidden
            overlayController.hide()
            if saveHistory {
                let normalized = normalizedHistoryText(trimmed)
                if !normalized.isEmpty {
                    history.insert(HistoryItem(text: normalized), at: 0)
                    historyData = try? JSONEncoder().encode(history)
                }
            }
            return
        }
        let shouldPaste = autoPaste && accessibilityAuthorized
        if autoPaste && !accessibilityAuthorized {
            logEvent("Auto-paste skipped: Accessibility not granted.")
        }
        let didPaste = pasteManager.paste(text: text, autoPaste: shouldPaste)
        if shouldPaste {
            if didPaste {
                logEvent("Auto-paste sent.")
                hideOverlay()
            } else {
                logEvent("Auto-paste skipped: no focused text input.")
                showOverlayToast(
                    message: "No focused text input. Click a field and try again.",
                    duration: 2.5
                )
            }
        } else {
            hideOverlay()
        }
        if saveHistory {
            let normalized = normalizedHistoryText(trimmed)
            if !normalized.isEmpty {
                history.insert(HistoryItem(text: normalized), at: 0)
                historyData = try? JSONEncoder().encode(history)
            }
        }
    }

    private func handleTranscriptionFailure(_ error: Error) {
        status = .idle
        errorMessage = error.localizedDescription
        logEvent("Transcription failed: \(error.localizedDescription)")
        showOverlayError(
            title: "Transcription failed",
            subtitle: error.localizedDescription
        )
    }

    func clearHistory() {
        history.removeAll()
        historyData = try? JSONEncoder().encode(history)
    }

    func deleteHistoryItem(_ item: HistoryItem) {
        history.removeAll { $0.id == item.id }
        historyData = try? JSONEncoder().encode(history)
    }

    var isOnboardingComplete: Bool {
        onboardingCompletedSteps == onboardingTotalSteps
    }

    var onboardingCompletedSteps: Int {
        var completed = 0
        if hotkeyConfigured { completed += 1 }
        if microphoneAuthorized { completed += 1 }
        if accessibilityAuthorized { completed += 1 }
        return completed
    }

    var onboardingTotalSteps: Int { 3 }

    var hotkeyConfigured: Bool {
        hotkeyData != nil || lastHotkeyDetectedAt != nil || hotkey == .default
    }

    var shouldShowOnboarding: Bool {
        onboardingPreviewMode || !onboardingFinished
    }

    func refreshInputDevice() {
        refreshInputDevices()
    }

    func refreshInputDevices() {
        defaultInputDeviceName = AudioDeviceManager.defaultInputDeviceName()
        availableInputDevices = AudioDeviceManager.availableInputDevices()
        if !selectedInputDeviceUID.isEmpty,
           !availableInputDevices.contains(where: { $0.uid == selectedInputDeviceUID }) {
            selectedInputDeviceUID = ""
            selectedInputDeviceUIDRaw = ""
        }
        inputDeviceName = selectedInputDeviceName()
    }

    func selectInputDevice(_ uid: String) {
        if uid == selectedInputDeviceUID {
            return
        }
        stopMicTest()
        selectedInputDeviceUID = uid
        selectedInputDeviceUIDRaw = uid
        refreshInputDevices()
        logEvent("Input device set to \(inputDeviceName).")
    }

    func selectedInputDeviceID() -> AudioDeviceID? {
        guard !selectedInputDeviceUID.isEmpty else { return nil }
        return availableInputDevices.first(where: { $0.uid == selectedInputDeviceUID })?.deviceID
    }

    private func ensureInputDeviceAvailable(context: String) -> Bool {
        refreshInputDevices()
        guard !availableInputDevices.isEmpty else {
            errorMessage = "No microphone detected."
            logEvent("No input device available (\(context)).")
            showOverlayError(
                title: "Microphone not detected",
                subtitle: "Connect a microphone and try again."
            )
            showOverlayToast(message: "No microphone detected. Connect one and try again.", duration: 3.5)
            return false
        }
        return true
    }

    private func selectedInputDeviceName() -> String {
        if !selectedInputDeviceUID.isEmpty,
           let selected = availableInputDevices.first(where: { $0.uid == selectedInputDeviceUID }) {
            return selected.name
        }
        return defaultInputDeviceName
    }

    @discardableResult
    private func maybeShowAirPodsWarning() -> Bool {
        guard status == .idle else { return false }
        guard let activeDeviceName = activeInputDeviceNameForWarning() else { return false }
        guard isAirPodsDeviceName(activeDeviceName) else {
            airPodsWarningSuppressedDeviceName = nil
            return false
        }
        guard airPodsWarningSuppressedDeviceName != activeDeviceName else { return false }
        showAirPodsWarning()
        return true
    }

    private func showAirPodsWarning() {
        overlayErrorToken = nil
        overlayToastToken = nil
        overlayState.status = .airPodsWarning
        overlayController.show()
        logEvent("AirPods input detected; showing warning.")
    }

    private func isAirPodsDeviceName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("airpods")
            || normalized.contains("air pods")
            || normalized.contains("airpod")
    }

    private func activeInputDeviceNameForWarning() -> String? {
        if !selectedInputDeviceUID.isEmpty {
            return availableInputDevices.first(where: { $0.uid == selectedInputDeviceUID })?.name
        }
        return availableInputDevices.first(where: { $0.isDefault })?.name
    }

    func startMicTest() {
        guard status == .idle else { return }
        if isMicTesting {
            stopMicTest()
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            refreshPermissionStatus()
            guard ensureInputDeviceAvailable(context: "mic-test") else { return }
            beginMicMonitoring()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.refreshPermissionStatus()
                    if !granted {
                        self.errorMessage = "Microphone access denied."
                        return
                    }
                    guard self.ensureInputDeviceAvailable(context: "mic-test") else { return }
                    self.beginMicMonitoring()
                }
            }
        case .denied, .restricted:
            errorMessage = "Microphone access denied."
            refreshPermissionStatus()
        @unknown default:
            errorMessage = "Microphone access unavailable."
            refreshPermissionStatus()
        }
    }

    func stopMicTest() {
        audioLevelMonitor.stop()
        isMicTesting = false
        micLevel = 0
        logEvent("Microphone test stopped.")
    }

    func startOnboardingDemo() {
        guard !isOnboardingDemoActive else { return }
        guard ensureInputDeviceAvailable(context: "onboarding-demo") else { return }
        isOnboardingDemoActive = true
        isHotkeyPressed = false
        onboardingDemoText = ""
        onboardingDemoFieldFocused = false
        warmUpTranscriptionIfNeeded(context: "onboarding-demo")
        guard microphoneAuthorized, !isMicTesting, !isDemoMicMonitoring else { return }
        do {
            try audioLevelMonitor.start(deviceID: selectedInputDeviceID()) { [weak self] level in
                self?.micLevel = level
            }
            isDemoMicMonitoring = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopOnboardingDemo() {
        guard isOnboardingDemoActive else { return }
        isOnboardingDemoActive = false
        isHotkeyPressed = false
        onboardingDemoFieldFocused = false
        guard isDemoMicMonitoring else { return }
        audioLevelMonitor.stop()
        micLevel = 0
        isDemoMicMonitoring = false
    }

    @discardableResult
    func requestAccessibilityAccess() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        debugAccessibilityStatus(context: "request")
        openAccessibilitySettings()
        if !granted {
            errorMessage = "Enable Accessibility for DictateGo in System Settings."
        }
        refreshPermissionStatus()
        return granted
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshPermissionStatus() {
        let previousMic = microphoneAuthorized
        let previousAccessibility = accessibilityAuthorized
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityAuthorized = AXIsProcessTrusted()
        debugAccessibilityStatus(context: "refresh")
        if microphoneAuthorized != previousMic {
            logEvent("Microphone \(microphoneAuthorized ? "granted" : "not granted").")
        }
        if accessibilityAuthorized != previousAccessibility {
            logEvent("Accessibility \(accessibilityAuthorized ? "granted" : "not granted").")
        }
        if accessibilityAuthorized {
            accessibilityRequestAttempts = 0
        }
        updateOnboardingProgress()
    }

    func noteAccessibilityRequestAttempt() {
        accessibilityRequestAttempts += 1
    }

    var shouldShowAccessibilityInstructions: Bool {
        accessibilityRequestAttempts >= 2 && !accessibilityAuthorized
    }

    var accessibilityEmphasisDetail: String? {
        guard shouldShowAccessibilityInstructions else { return nil }
        return "If DictateGo is missing, click + and add it."
    }

    func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionStatus()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func debugAccessibilityStatus(context: String) {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let trusted = AXIsProcessTrusted()
        if diagnosticsEnabled {
            logEvent("Accessibility check (\(context)): bundleId=\(bundleId), trusted=\(trusted).")
        }
        #if DEBUG
        print("Accessibility check (\(context)): bundleId=\(bundleId), trusted=\(trusted)")
        #endif
    }

    private func scheduleHotkeyRefresh() {
        hotkeyRefreshTimer?.invalidate()
        hotkeyRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hotkeyMonitor.restartMonitoring()
            }
        }
        RunLoop.main.add(hotkeyRefreshTimer!, forMode: .common)
    }

    private func beginMicMonitoring() {
        do {
            try audioLevelMonitor.start(deviceID: selectedInputDeviceID()) { [weak self] level in
                self?.micLevel = level
            }
            isMicTesting = true
            errorMessage = nil
            logEvent("Microphone test started.")
        } catch {
            errorMessage = error.localizedDescription
            logEvent("Microphone test failed: \(error.localizedDescription)")
        }
    }

    func clearEventLog() {
        eventLog.removeAll()
    }

    func startDiagnosticsSession() {
        diagnosticsEnabled = true
        clearEventLog()
        logEvent("Diagnostics started.")
    }

    func stopDiagnosticsSession() {
        diagnosticsEnabled = false
        clearEventLog()
    }

    private func logEvent(_ message: String) {
        guard diagnosticsEnabled else { return }
        let entry = EventLogEntry(timestamp: Date(), message: message)
        eventLog.append(entry)
        let maxEntries = 200
        if eventLog.count > maxEntries {
            eventLog.removeFirst(eventLog.count - maxEntries)
        }
    }

    private func warmUpTranscriptionIfNeeded(context: String) {
        guard !isTranscriptionWarm else { return }
        guard !isTranscriptionWarming else { return }
        isTranscriptionWarming = true
        transcriptionWarmupTask?.cancel()
        transcriptionWarmupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await transcription.loadModelIfNeeded(self.selectedModel)
                await MainActor.run {
                    self.isTranscriptionWarm = true
                    self.isTranscriptionWarming = false
                    self.logEvent("Transcription warm-up completed (\(context)).")
                }
            } catch {
                await MainActor.run {
                    self.isTranscriptionWarm = false
                    self.isTranscriptionWarming = false
                    self.logEvent("Transcription warm-up failed (\(context)): \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleHotkeyPress() {
        isHotkeyPressed = true
        if isOnboardingDemoActive && !onboardingDemoFieldFocused {
            logEvent("Hotkey ignored: onboarding demo not focused.")
            return
        }
        switch activationMode {
        case .hold:
            if maybeShowAirPodsWarning() { return }
            startRecording()
        case .toggle:
            if status == .recording {
                stopRecording()
            } else if status == .idle {
                if maybeShowAirPodsWarning() { return }
                startRecording()
            } else {
                logEvent("Hotkey ignored: status \(status.rawValue).")
            }
        }
    }

    private func handleHotkeyRelease() {
        isHotkeyPressed = false
        guard activationMode == .hold else { return }
        stopRecording()
    }

    private func startToggleTimers() {
        toggleMaxTimer?.invalidate()
        toggleMaxTimer = Timer.scheduledTimer(withTimeInterval: toggleMaxDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.status == .recording else { return }
                self.logEvent("Auto stop: max duration reached.")
                self.stopRecording()
            }
        }
        RunLoop.main.add(toggleMaxTimer!, forMode: .common)
    }

    private func stopToggleTimers() {
        toggleMaxTimer?.invalidate()
        toggleMaxTimer = nil
        lastSpeechAt = nil
        silenceStopTriggered = false
    }

    private func handleToggleSilence(level: Float) {
        guard activationMode == .toggle else { return }
        guard status == .recording else { return }
        if level >= toggleSilenceThreshold {
            lastSpeechAt = Date()
            silenceStopTriggered = false
            return
        }

        guard let lastSpeechAt else { return }
        let idleDuration = Date().timeIntervalSince(lastSpeechAt)
        if idleDuration >= toggleSilenceTimeout && !silenceStopTriggered {
            silenceStopTriggered = true
            logEvent("Auto stop: silence detected.")
            stopRecording()
        }
    }

    private func showOverlayError(title: String, subtitle: String) {
        overlayToastToken = nil
        overlayErrorToken = UUID()
        let token = overlayErrorToken
        overlayState.errorTitle = title
        overlayState.errorSubtitle = subtitle
        overlayState.status = .error
        showOverlayIfAllowed()
        logEvent("Overlay error: \(title)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self, self.overlayErrorToken == token else { return }
            self.hideOverlay()
        }
    }

    private func hideOverlay() {
        overlayState.status = .hidden
        overlayController.hide()
    }

    private func handleOverlayDismiss() {
        if let token = overlayToastToken {
            dismissOverlayToast(token: token)
            return
        }
        if overlayState.status == .airPodsWarning {
            airPodsWarningSuppressedDeviceName = inputDeviceName
            overlayState.status = .hidden
            overlayController.hide()
            return
        }
        hideOverlay()
    }

    private func dismissOverlayToast(token: UUID) {
        guard overlayToastToken == token else { return }
        overlayToastToken = nil
        restoreOverlayAfterToast()
    }

    private func restoreOverlayAfterToast() {
        switch status {
        case .recording:
            let speakingThreshold: Float = 0.2
            overlayState.status = overlayState.audioLevel > speakingThreshold ? .speaking : .recording
            showOverlayIfAllowed()
        case .transcribing:
            overlayState.status = .transcribing
            showOverlayIfAllowed()
        case .idle:
            hideOverlay()
        }
    }

    private func showOverlayToast(message: String, duration: TimeInterval) {
        overlayErrorToken = nil
        let token = UUID()
        overlayToastToken = token
        overlayState.toastMessage = message
        overlayState.toastDuration = duration
        overlayState.status = .toast
        showOverlayIfAllowed()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            self.dismissOverlayToast(token: token)
        }
    }

    private func showOverlayIfAllowed() {
        guard showRecordingBar else { return }
        overlayController.show()
    }

    private func updateOverlayVisibilityForSetting() {
        if showRecordingBar, overlayState.status != .hidden {
            overlayController.show()
        } else {
            overlayController.hide()
        }
    }

    private func updateOnboardingProgress() {
        guard !onboardingPreviewMode else { return }
        guard isOnboardingComplete else { return }
        guard onboardingStep != .welcome else { return }
        if onboardingStep != .complete {
            onboardingStep = .complete
        }
        if !onboardingFinished {
            onboardingFinished = true
        }
    }

    func startOnboardingPreview() {
        onboardingPreviewMode = true
        onboardingFinished = false
        onboardingStep = .welcome
        hotkeyData = nil
        lastHotkeyDetectedAt = nil
        lastHotkeyDetectedAtRaw = 0
    }

    func resetOnboardingForRestart(shouldClearHistory: Bool = true) {
        onboardingPreviewMode = false
        onboardingFinished = false
        onboardingStep = .welcome
        hasLaunchedBefore = false
        accessibilityRequestAttempts = 0
        if shouldClearHistory {
            clearHistory()
        }
        refreshModelStatus()
    }

    private func updateLoginItemSetting() {
        guard !isRunningInPreview else { return }
        let status = SMAppService.mainApp.status
        do {
            if openAtLogin {
                if status != .enabled {
                    try SMAppService.mainApp.register()
                    logEvent("Enabled open at login.")
                }
            } else if status == .enabled {
                try SMAppService.mainApp.unregister()
                logEvent("Disabled open at login.")
            }
        } catch {
            logEvent("Open at login update failed: \(error.localizedDescription)")
        }
    }

    private var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private func playStartSound() {
        guard playSounds else { return }
        startSound?.volume = soundVolume
        startSound?.play()
    }

    private func requestMicrophoneAccessIfNeeded() {
        guard !isRequestingMicAccess else { return }
        isRequestingMicAccess = true
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.isRequestingMicAccess = false
                self.refreshPermissionStatus()
                if !granted {
                    self.errorMessage = "Microphone access denied."
                    self.showOverlayError(
                        title: "Microphone access required",
                        subtitle: "Enable microphone access in System Settings."
                    )
                }
            }
        }
    }

    @discardableResult
    private func pauseSystemAudioIfNeeded() -> Bool {
        guard pauseSystemAudio else { return false }
        guard SystemAudioController.shouldPauseSystemAudio() else {
            pausedSystemAudioForRecording = false
            logEvent("System audio pause skipped: no active playback.")
            return false
        }
        SystemAudioController.togglePlayPause(shouldPreventMusicLaunch: true)
        pausedSystemAudioForRecording = true
        logEvent("System audio paused.")
        return true
    }

    private func resumeSystemAudioIfNeeded() {
        guard pausedSystemAudioForRecording else { return }
        SystemAudioController.togglePlayPause(shouldPreventMusicLaunch: false)
        pausedSystemAudioForRecording = false
        logEvent("System audio resumed.")
    }

    private func normalizedHistoryText(_ text: String) -> String {
        let invisibleScalars = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{FEFF}")
        let withoutInvisible = text.unicodeScalars.filter { !invisibleScalars.contains($0) }
        let withoutNbsp = String(String.UnicodeScalarView(withoutInvisible))
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let trimmed = withoutNbsp.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed
            .split { $0.isWhitespace || $0.isNewline }
            .joined(separator: " ")
        return collapsed
    }

}

struct EventLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

struct HistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let timestamp: Date

    init(id: UUID = UUID(), text: String, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
}

#if DEBUG
extension AppState {
    static func preview() -> AppState {
        let state = AppState(preview: true)
        state.microphoneAuthorized = true
        state.accessibilityAuthorized = true
        state.availableInputDevices = [
            AudioInputDevice(deviceID: 0, uid: "preview-default", name: "Built-in Microphone", isDefault: true)
        ]
        state.defaultInputDeviceName = "Built-in Microphone"
        state.selectedInputDeviceUID = ""
        state.micLevel = 0.2
        state.modelStatus = .ready
        state.isTranscriptionWarm = true
        state.activationMode = .hold
        state.openAtLogin = false
        state.showRecordingBar = true
        state.playSounds = true
        return state
    }
}
#endif
