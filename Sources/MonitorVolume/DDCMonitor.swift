import AppleSiliconDDC
import Foundation
import VolumeCore

struct DDCMonitor {
    let details: AppleSiliconDDC.IOregService

    var identity: MonitorIdentity {
        // The physical connection disambiguates identical models; EDID protects against replacement.
        MonitorIdentity(id: details.ioDisplayLocation + "|" + details.edidUUID, name: details.productName)
    }

    static func discover() -> [DDCMonitor] {
        guard AppleSiliconDDC.isArm64 else { return [] }
        var seen = Set<String>()
        return AppleSiliconDDC.getIoregServicesForMatching().compactMap { details in
            // Keep even inaccessible services in the candidate set so an identical
            // monitor without DDC access cannot make another monitor look unique.
            guard details.location == "External",
                  !details.productName.isEmpty, !details.ioDisplayLocation.isEmpty else { return nil }
            let monitor = DDCMonitor(details: details)
            guard seen.insert(monitor.identity.id).inserted else { return nil }
            return monitor
        }
    }

    func readVolume() -> VolumeState? {
        guard let result = AppleSiliconDDC.read(service: details.service, command: 0x62,
                                              numOfRetryAttemps: 1) else { return nil }
        return VolumeState(current: Int(result.current), maximum: Int(result.max))
    }

    func writeVolume(_ value: Int) -> Bool {
        guard (0...65535).contains(value) else { return false }
        return AppleSiliconDDC.write(service: details.service, command: 0x62, value: UInt16(value),
                                    numOfRetryAttemps: 1)
    }
}
