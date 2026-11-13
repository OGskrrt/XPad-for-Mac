import Foundation

/// `XPad --selftest [seconds]` prints controller input to the terminal without any UI.
enum SelfTest {
    static func run(seconds: Double) -> Never {
        let usb = USBPad()
        var last: PadState?
        usb.onDevice = { print("device:", $0 ?? "none"); fflush(stdout) }
        usb.onBusy = { if let o = $0 { print("busy: in use by", o); fflush(stdout) } }
        usb.onState = { s in
            guard s != last else { return }
            last = s
            let pressed = Btn.allCases.filter { s.has($0) }.map { "\($0)" }.joined(separator: " ")
            print(String(format: "buttons:[%@] LT:%.2f RT:%.2f L:(%.2f,%.2f) R:(%.2f,%.2f)",
                         pressed, s.lt, s.rt, s.lx, s.ly, s.rx, s.ry))
            fflush(stdout)
        }
        usb.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { print("done"); exit(0) }
        dispatchMain()
    }
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--selftest") {
    let secs = args.count > i + 1 ? Double(args[i + 1]) ?? 20 : 20
    SelfTest.run(seconds: secs)
}
// One copy only: if XPad is already running, bring its window forward and quit.
import AppKit
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != NSRunningApplication.current }) {
    DistributedNotificationCenter.default().postNotificationName(showWindowNote, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}
XPadApp.main()
