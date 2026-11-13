import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement

let helpURL = URL(string: "https://ogskrrt.github.io/XPad-for-Mac/")!

final class AppModel: ObservableObject {
    @Published var deviceName: String?
    @Published var busyBy: String?
    @Published var state = PadState()
    @Published var trusted = AXIsProcessTrusted()
    @Published var loginOn = SMAppService.mainApp.status == .enabled
    @Published var mappingOn: Bool {
        didSet { UserDefaults.standard.set(mappingOn, forKey: "mappingOn"); pushMapping() }
    }
    @Published var profileID: String {
        didSet { UserDefaults.standard.set(profileID, forKey: "profile"); pushMapping() }
    }
    @Published var paused = false {
        didSet { usb.setPaused(paused) }
    }

    let usb = USBPad()
    let mapper: Mapper
    private let lock = NSLock()
    private var latest = PadState()
    private var uiPending = false
    private var axTimer: Timer?

    init() {
        let d = UserDefaults.standard
        mappingOn = d.object(forKey: "mappingOn") as? Bool ?? true
        profileID = d.string(forKey: "profile") ?? "arrows"
        mapper = Mapper(queue: usb.queue)

        let mapper = self.mapper
        usb.onState = { [weak self] s in
            mapper.apply(s)
            self?.publish(s)
        }
        usb.onDevice = { [weak self] name in
            DispatchQueue.main.async { self?.deviceName = name }
        }
        usb.onBusy = { [weak self] owner in
            DispatchQueue.main.async { if self?.busyBy != owner { self?.busyBy = owner } }
        }
        pushMapping()
        usb.start()

        axTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = AXIsProcessTrusted()
            if t != self.trusted { self.trusted = t }
        }
        if mappingOn && !trusted { askForAccessibility() }
    }

    private func pushMapping() {
        mapper.configure(enabled: mappingOn, profile: Profiles.byID(profileID))
    }

    /// Coalesce UI updates to ~60 per second.
    private func publish(_ s: PadState) {
        lock.lock()
        latest = s
        let schedule = !uiPending
        uiPending = true
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let v = self.latest
            self.uiPending = false
            self.lock.unlock()
            if self.state != v { self.state = v }
        }
    }

    func askForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func openAccessibilitySettings() {
        askForAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("XPad login item: \(error.localizedDescription)")
        }
        loginOn = SMAppService.mainApp.status == .enabled
    }
}

/// `--preview` also shows the panel in a normal window (for screenshots).
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?
    var window: NSWindow?
    func applicationDidFinishLaunching(_ n: Notification) {
        guard CommandLine.arguments.contains("--preview"), let model = Self.model else { return }
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "XPad"
        w.contentView = NSHostingView(rootView: PanelView().environmentObject(model)
            .background(Color(nsColor: .windowBackgroundColor)))
        if CommandLine.arguments.contains("--light") { w.appearance = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--dark") { w.appearance = NSAppearance(named: .darkAqua) }
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
        let args = CommandLine.arguments
        if args.contains("--demo") {
            model.deviceName = "Ultimate C 2.4G Wireless Controller"
            var st = PadState()
            st.buttons = (1 << UInt32(Btn.a.rawValue)) | (1 << UInt32(Btn.rb.rawValue))
            st.rt = 0.7; st.lx = -0.6; st.ly = 0.3
            model.state = st
        }
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
            let path = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard let v = w.contentView,
                      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(v.bounds.width * 2),
                                                 pixelsHigh: Int(v.bounds.height * 2), bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
                else { return }
                rep.size = v.bounds.size
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }
}

struct XPadApp: App {
    @NSApplicationDelegateAdaptor(PreviewDelegate.self) private var delegate
    @StateObject private var model: AppModel

    init() {
        let m = AppModel()
        PreviewDelegate.model = m
        _model = StateObject(wrappedValue: m)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(model)
        } label: {
            Image(systemName: model.deviceName == nil ? "gamecontroller" : "gamecontroller.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Panel

struct PanelView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("XPad").font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 8)
                StatusPill(name: m.paused ? nil : m.deviceName, paused: m.paused)
            }

            PadView(s: m.state, connected: m.deviceName != nil && !m.paused)
                .frame(maxWidth: .infinity)

            if m.paused {
                hint("Paused. The controller is free for other apps (for example the XPad Chrome extension).")
            } else if m.deviceName == nil, let owner = m.busyBy {
                hint("The controller is in use by \(owner). Close it there (for example the bridge tab in Chrome) and XPad connects by itself.")
            } else if m.deviceName == nil {
                hint("Plug in an Xbox 360-style controller (or its USB receiver) and switch the controller on.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use as keyboard & mouse", isOn: $m.mappingOn)
                    .toggleStyle(.switch)
                Picker("Layout", selection: $m.profileID) {
                    ForEach(Profiles.all) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
                .disabled(!m.mappingOn)
                Text(Profiles.byID(m.profileID).summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if m.mappingOn && !m.trusted {
                PermissionBox()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Pause", isOn: $m.paused)
                Toggle("Open at login", isOn: Binding(get: { m.loginOn }, set: { m.setLogin($0) }))
            }

            HStack {
                Link("Help", destination: helpURL).font(.callout)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct StatusPill: View {
    let name: String?
    let paused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(name != nil ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(paused ? "Paused" : (name ?? "No controller"))
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .frame(maxWidth: 170, alignment: .trailing)
    }
}

struct PermissionBox: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("One permission needed", systemImage: "lock.open")
                .font(.callout.weight(.semibold))
            Text("macOS only lets XPad press keys for you if you allow it: System Settings › Privacy & Security › Accessibility › XPad.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") { m.openAccessibilitySettings() }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.13)))
    }
}

// MARK: - Live controller

struct PadView: View {
    let s: PadState
    let connected: Bool

    private let on = Color.accentColor
    private let off = Color.secondary.opacity(0.28)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
                .frame(width: 262, height: 104)
                .position(x: 134, y: 76)

            trigger(s.lt, x: 62)
            trigger(s.rt, x: 206)
            bumper(s.has(.lb), x: 62)
            bumper(s.has(.rb), x: 206)

            stick(s.lx, s.ly, pressed: s.has(.ls), at: CGPoint(x: 66, y: 66))
            stick(s.rx, s.ry, pressed: s.has(.rs), at: CGPoint(x: 166, y: 100))

            dpad(at: CGPoint(x: 102, y: 100))

            face("Y", s.has(.y), at: CGPoint(x: 204, y: 48))
            face("A", s.has(.a), at: CGPoint(x: 204, y: 84))
            face("X", s.has(.x), at: CGPoint(x: 186, y: 66))
            face("B", s.has(.b), at: CGPoint(x: 222, y: 66))

            small(s.has(.back), at: CGPoint(x: 116, y: 60))
            small(s.has(.home), at: CGPoint(x: 134, y: 46), round: true)
            small(s.has(.start), at: CGPoint(x: 152, y: 60))
        }
        .frame(width: 268, height: 132)
        .opacity(connected ? 1 : 0.45)
        .animation(.easeOut(duration: 0.06), value: s)
        .accessibilityElement()
        .accessibilityLabel("Live controller view")
    }

    private func trigger(_ v: Double, x: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(off).frame(width: 52, height: 6)
            Capsule().fill(on).frame(width: max(0, 52 * v), height: 6)
        }
        .frame(width: 52, height: 6)
        .position(x: x, y: 6)
    }

    private func bumper(_ p: Bool, x: CGFloat) -> some View {
        Capsule().fill(p ? on : off).frame(width: 52, height: 9).position(x: x, y: 20)
    }

    private func stick(_ x: Double, _ y: Double, pressed: Bool, at c: CGPoint) -> some View {
        ZStack {
            Circle().stroke(off, lineWidth: 2).frame(width: 34, height: 34)
            Circle().fill(pressed ? on : on.opacity(0.75)).frame(width: 14, height: 14)
                .offset(x: x * 10, y: -y * 10)
        }
        .position(c)
    }

    private func dpad(at c: CGPoint) -> some View {
        ZStack {
            arm(s.has(.up)).offset(y: -11)
            arm(s.has(.down)).offset(y: 11)
            arm(s.has(.left)).offset(x: -11)
            arm(s.has(.right)).offset(x: 11)
        }
        .position(c)
    }

    private func arm(_ p: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(p ? on : off).frame(width: 11, height: 11)
    }

    private func face(_ t: String, _ p: Bool, at c: CGPoint) -> some View {
        ZStack {
            Circle().fill(p ? on : off).frame(width: 17, height: 17)
            Text(t).font(.system(size: 9, weight: .bold)).foregroundStyle(p ? Color.white : Color.primary.opacity(0.6))
        }
        .position(c)
    }

    private func small(_ p: Bool, at c: CGPoint, round: Bool = false) -> some View {
        Group {
            if round { Circle().fill(p ? on : off).frame(width: 12, height: 12) }
            else { Capsule().fill(p ? on : off).frame(width: 13, height: 7) }
        }
        .position(c)
    }
}
