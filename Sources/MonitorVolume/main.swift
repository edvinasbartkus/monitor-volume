import AppKit
import AppleSiliconDDC
import ApplicationServices
import VolumeCore

if CommandLine.arguments.contains("--diagnose") {
    print("Monitor Volume diagnostics (read-only; no volume changes)")
    print("Apple Silicon: \(AppleSiliconDDC.isArm64)")
    print("Accessibility permission: \(AXIsProcessTrusted())")
    print("Input Monitoring permission: \(CGPreflightListenEventAccess())")
    let output = AudioOutput.current()
    print("Default output: \(output?.name ?? "None")")
    print("Display audio transport: \(output?.isDisplay ?? false)")
    let monitors = DDCMonitor.discover()
    for monitor in monitors {
        print("Monitor: \(monitor.identity.name)")
        print("  Connection: \(monitor.details.ioDisplayLocation)")
        if let volume = monitor.readVolume() {
            print("  Volume: \(volume.current)/\(volume.maximum) (\(volume.percent)%)")
        } else {
            print("  Volume: DDC read failed or unsupported")
        }
    }
    let explicitID = output.flatMap {
        (UserDefaults.standard.dictionary(forKey: "OutputMonitorLinks") as? [String: String])?[$0.uid]
    }
    let displayOutputNames = AudioOutput.displayOutputs()?.map(\.name) ?? []
    print("Connected display audio outputs: \(displayOutputNames.joined(separator: ", "))")
    let matched = output.flatMap {
        RouteMatcher.match(outputName: $0.name, isDisplayOutput: $0.isDisplay,
                           displayOutputNames: displayOutputNames,
                           monitors: monitors.map(\.identity), explicitID: explicitID)
    }
    print("Matched monitor: \(matched?.name ?? "None (use the link menu if necessary)")")
} else {
    guard AppleSiliconDDC.isArm64 else {
        fputs("Monitor Volume currently supports Apple Silicon Macs only.\n", stderr)
        exit(1)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
