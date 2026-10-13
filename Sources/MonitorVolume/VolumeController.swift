import AppKit
import VolumeCore

/// All UI state is main-thread confined. Only DDC operations run on the serial worker.
final class VolumeController {
    var onChange: (() -> Void)?
    private(set) var output: AudioOutput?
    private(set) var monitors: [DDCMonitor] = []
    private(set) var volume: VolumeState?
    private(set) var status = "Detecting monitor…"
    var paused = false
    private(set) var stepPercent = VolumeStep.validated(UserDefaults.standard.integer(forKey: "VolumeStepPercent"))
    private let queue = DispatchQueue(label: "MonitorVolume.DDC", qos: .userInitiated)
    private var generation = 0
    private var revision = 0
    private var lease: RouteLease?
    private var pendingValue: Int?
    private var writing = false
    private var polling = false
    private var observer: AudioOutputObserver?
    private var timer: Timer?
    private var lastPoll = Date.distantPast
    private var notificationTokens: [NSObjectProtocol] = []
    private var sleeping = false
    private var rememberedVolumes: [String: Int] = [:]

    var isReady: Bool { !paused && !sleeping && volume != nil && lease != nil }

    func setStepPercent(_ percentage: Int) {
        guard VolumeStep.supportedPercentages.contains(percentage) else { return }
        stepPercent = percentage
        UserDefaults.standard.set(percentage, forKey: "VolumeStepPercent")
        onChange?()
    }

    func start() {
        observer = AudioOutputObserver { [weak self] in self?.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.sleeping else { return }
            if AudioOutput.current() != self.output { self.refresh() }
            else { self.pollVolume() }
        }
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() })
        notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.sleeping = true
            self?.refresh()
        })
        notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.sleeping = false
            self?.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refresh() }
        })
        refresh()
    }

    func refresh() {
        generation += 1
        let token = generation
        if let lease, let volume { rememberedVolumes[lease.monitor.identity.id] = volume.restoreValue }
        lease?.invalidate()
        lease = nil
        volume = nil
        pendingValue = nil
        writing = false
        polling = false
        output = AudioOutput.current()
        guard !sleeping else { status = "Sleeping"; onChange?(); return }
        status = paused ? "Paused — normal volume keys" : "Detecting monitor…"
        onChange?()
        let expectedOutput = output
        let explicitID = expectedOutput.flatMap { mappings[$0.uid] }
        let displayOutputNames = AudioOutput.displayOutputs()?.map(\.name) ?? []
        queue.async { [weak self] in
            let monitors = DDCMonitor.discover()
            let identity = expectedOutput.flatMap {
                RouteMatcher.match(outputName: $0.name, isDisplayOutput: $0.isDisplay,
                                   displayOutputNames: displayOutputNames,
                                   monitors: monitors.map(\.identity), explicitID: explicitID)
            }
            let monitor = monitors.first { $0.identity == identity }
            let volume = monitor?.readVolume()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                guard AudioOutput.current() == expectedOutput else { self.refresh(); return }
                self.monitors = monitors
                if self.paused { self.status = "Paused — normal volume keys" }
                else if expectedOutput == nil { self.status = "No default audio output" }
                else if expectedOutput?.isDisplay != true { self.status = "Normal volume keys — not a monitor output" }
                else if monitor == nil { self.status = "No unique match — link output below" }
                else if volume == nil { self.status = "DDC volume unavailable — enable DDC/CI, then Refresh" }
                else if let monitor, let volume, let expectedOutput {
                    self.lease = RouteLease(outputUID: expectedOutput.uid, monitor: monitor)
                    self.volume = VolumeState(current: volume.current, maximum: volume.maximum,
                                              restoreValue: self.rememberedVolumes[monitor.identity.id])
                    self.status = "Monitor volume: \(volume.percent)%"
                    self.lastPoll = Date()
                }
                self.onChange?()
            }
        }
    }

    /// Returns true only when the key belongs to a currently usable monitor route.
    @discardableResult
    func handle(_ action: VolumeAction?, fine: Bool = false) -> Bool {
        guard isReady, let lease, lease.isValid,
              AudioOutput.current()?.uid == lease.outputUID, var state = volume else { return false }
        guard let action else { return true }
        state.apply(action, stepPercent: stepPercent, fine: fine)
        volume = state
        rememberedVolumes[lease.monitor.identity.id] = state.restoreValue
        revision += 1
        pendingValue = state.current
        status = "Monitor volume: \(state.percent)%"
        // No I2C, rendering, or menu reconstruction inside the event tap callback.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onChange?()
            self.drainWrites()
        }
        return true
    }

    private func drainWrites() {
        guard !writing, let value = pendingValue, let lease, isReady else { return }
        pendingValue = nil
        writing = true
        let token = generation
        queue.async { [weak self] in
            guard lease.isValid, AudioOutput.current()?.uid == lease.outputUID else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.refresh()
                }
                return
            }
            let sent = lease.monitor.writeVolume(value)
            // A successful I2C write alone does not prove the monitor accepted the value.
            let confirmed = sent ? lease.monitor.readVolume() : nil
            let success = confirmed?.current == value
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.writing = false
                guard AudioOutput.current()?.uid == lease.outputUID else { self.refresh(); return }
                guard success else {
                    lease.invalidate()
                    self.lease = nil
                    self.volume = nil
                    self.pendingValue = nil
                    self.status = "DDC write not confirmed — keys released; try Refresh"
                    self.onChange?()
                    return
                }
                self.lastPoll = Date()
                self.drainWrites()
                self.onChange?()
            }
        }
    }

    private func pollVolume() {
        guard isReady, !writing, pendingValue == nil, !polling,
              Date().timeIntervalSince(lastPoll) >= 5, let lease else { return }
        polling = true
        let token = generation
        let oldRevision = revision
        queue.async { [weak self] in
            let result = lease.isValid ? lease.monitor.readVolume() : nil
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.polling = false
                self.lastPoll = Date()
                guard self.revision == oldRevision, !self.writing, self.pendingValue == nil else { return }
                guard AudioOutput.current()?.uid == lease.outputUID else { self.refresh(); return }
                guard let result, result.maximum == self.volume?.maximum else {
                    self.refresh()
                    return
                }
                self.volume?.synchronize(current: result.current)
                self.status = "Monitor volume: \(result.percent)%"
                self.onChange?()
            }
        }
    }

    func link(outputUID: String, monitorID: String?) {
        guard let output, output.isDisplay, output.uid == outputUID,
              AudioOutput.current()?.uid == outputUID else { refresh(); return }
        if let monitorID, !monitors.contains(where: { $0.identity.id == monitorID }) { refresh(); return }
        var saved = mappings
        saved[output.uid] = monitorID
        UserDefaults.standard.set(saved, forKey: "OutputMonitorLinks")
        refresh()
    }

    var selectedLink: String? { output.flatMap { mappings[$0.uid] } }
    private var mappings: [String: String] {
        UserDefaults.standard.dictionary(forKey: "OutputMonitorLinks") as? [String: String] ?? [:]
    }
}

/// Invalidates queued writes on output/device changes without sharing mutable UI state.
private final class RouteLease {
    let outputUID: String
    let monitor: DDCMonitor
    private let lock = NSLock()
    private var valid = true
    init(outputUID: String, monitor: DDCMonitor) { self.outputUID = outputUID; self.monitor = monitor }
    var isValid: Bool { lock.lock(); defer { lock.unlock() }; return valid }
    func invalidate() { lock.lock(); defer { lock.unlock() }; valid = false }
}
