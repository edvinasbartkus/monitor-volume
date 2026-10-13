import Foundation

public enum VolumeAction: Equatable {
    case up, down, mute
}

public enum VolumeStep {
    public static let supportedPercentages = [1, 2, 3, 5, 6]
    public static let defaultPercentage = 1

    public static func validated(_ percentage: Int) -> Int {
        supportedPercentages.contains(percentage) ? percentage : defaultPercentage
    }
}

/// Mute is volume zero, rather than the inconsistently implemented VCP mute command.
public struct VolumeState: Equatable {
    public private(set) var current: Int
    public let maximum: Int
    public private(set) var restoreValue: Int

    public init?(current: Int, maximum: Int, restoreValue: Int? = nil) {
        guard maximum > 0, maximum <= 65535, (0...maximum).contains(current) else { return nil }
        self.current = current
        self.maximum = maximum
        self.restoreValue = current > 0 ? current : min(maximum, max(1, restoreValue ?? (maximum / 4)))
    }

    public var percent: Int { Int((Double(current) / Double(maximum) * 100).rounded()) }

    public mutating func apply(_ action: VolumeAction, stepPercent: Int = VolumeStep.defaultPercentage, fine: Bool = false) {
        let percentage = fine ? 1 : min(100, max(1, stepPercent))
        // Hardware registers have integer resolution; always move at least one unit.
        let step = max(1, Int((Double(maximum) * Double(percentage) / 100).rounded()))
        switch action {
        case .up: current = min(maximum, current + step)
        case .down: current = max(0, current - step)
        case .mute:
            if current > 0 {
                restoreValue = current
                current = 0
            } else {
                current = min(maximum, restoreValue)
            }
        }
        if current > 0 { restoreValue = current }
    }

    public mutating func synchronize(current: Int) {
        guard (0...maximum).contains(current) else { return }
        self.current = current
        if current > 0 { restoreValue = current }
    }
}

public struct MonitorIdentity: Equatable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum RouteMatcher {
    /// Never guess based on the cursor or the mere presence of one external monitor.
    public static func match(outputName: String, isDisplayOutput: Bool,
                             displayOutputNames: [String], monitors: [MonitorIdentity],
                             explicitID: String? = nil) -> MonitorIdentity? {
        guard isDisplayOutput else { return nil }
        if explicitID == nil {
            guard displayOutputNames.filter({ normalize($0) == normalize(outputName) }).count == 1 else { return nil }
        }
        let candidates = monitors.filter {
            if let explicitID { return $0.id == explicitID }
            return normalize($0.name) == normalize(outputName)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct MediaKey: Equatable {
    public let action: VolumeAction
    public let isDown: Bool
    public let isRepeat: Bool

    public static func decode(data1: Int, subtype: Int) -> MediaKey? {
        guard subtype == 8 else { return nil }
        let code = (data1 >> 16) & 0xffff
        let state = (data1 >> 8) & 0xff
        guard state == 0x0a || state == 0x0b else { return nil }
        let action: VolumeAction
        switch code {
        case 0: action = .up
        case 1: action = .down
        case 7: action = .mute
        default: return nil
        }
        return MediaKey(action: action, isDown: state == 0x0a, isRepeat: (data1 & 1) != 0)
    }
}
