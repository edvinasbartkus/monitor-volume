import AppKit
import ApplicationServices
import VolumeCore

final class MediaKeyTap {
    // nil action checks ownership without applying a repeated mute toggle.
    var onKey: ((VolumeAction?, Bool) -> Bool)?
    var onAvailabilityChange: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var captured = Set<Int>()
    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() {
        guard tap == nil else {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard AXIsProcessTrusted() else { return }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<MediaKeyTap>.fromOpaque(context).takeUnretainedValue()
            return owner.receive(type: type, event: event)
        }
        // systemDefined is event type 14 (not a named CGEventType constant).
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: CGEventMask(1) << 14,
                                         callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        captured.removeAll()
    }

    private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            captured.removeAll()
            if let tap, AXIsProcessTrusted() { CGEvent.tapEnable(tap: tap, enable: true) }
            // Keep expensive work out of the event tap callback.
            DispatchQueue.main.async { [weak self] in self?.onAvailabilityChange?() }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event),
              let key = MediaKey.decode(data1: nsEvent.data1, subtype: Int(nsEvent.subtype.rawValue)) else {
            return Unmanaged.passUnretained(event)
        }
        let code = (nsEvent.data1 >> 16) & 0xffff
        if !key.isDown {
            return captured.remove(code) != nil ? nil : Unmanaged.passUnretained(event)
        }
        // Ignore mute repeats without toggling, but still re-evaluate route ownership.
        let action = key.action == .mute && key.isRepeat ? nil : key.action
        let fine = nsEvent.modifierFlags.contains([.shift, .option])
        if onKey?(action, fine) == true {
            captured.insert(code)
            return nil
        }
        // If a repeat now belongs to native audio, relinquish its eventual key-up too.
        captured.remove(code)
        return Unmanaged.passUnretained(event)
    }

    deinit { stop() }
}
