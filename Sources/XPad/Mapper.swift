import Foundation
import CoreGraphics

/// Something on the controller that can be bound.
enum Ctl: Hashable {
    case btn(Btn), lt, rt
    case lUp, lDown, lLeft, lRight, rUp, rDown, rLeft, rRight
}

enum Act {
    case key(CGKeyCode, CGEventFlags)
    case click(CGMouseButton)
}

enum StickUse { case keys, mouse, scroll, off }

struct Profile: Identifiable {
    let id: String
    let name: String
    let summary: String
    let left: StickUse
    let right: StickUse
    let binds: [Ctl: Act]
}

/// macOS virtual key codes (ANSI layout).
enum K {
    static let a = CGKeyCode(0), s = CGKeyCode(1), d = CGKeyCode(2), z = CGKeyCode(6), x = CGKeyCode(7)
    static let c = CGKeyCode(8), v = CGKeyCode(9), q = CGKeyCode(12), w = CGKeyCode(13), e = CGKeyCode(14)
    static let r = CGKeyCode(15), f = CGKeyCode(3), rightBracket = CGKeyCode(30), leftBracket = CGKeyCode(33)
    static let ret = CGKeyCode(36), tab = CGKeyCode(48), space = CGKeyCode(49), esc = CGKeyCode(53)
    static let cmd = CGKeyCode(55), shift = CGKeyCode(56), option = CGKeyCode(58), control = CGKeyCode(59)
    static let left = CGKeyCode(123), right = CGKeyCode(124), down = CGKeyCode(125), up = CGKeyCode(126)
}

private func key(_ k: CGKeyCode, _ f: CGEventFlags = []) -> Act { .key(k, f) }

enum Profiles {
    private static let dpadArrows: [Ctl: Act] = [
        .btn(.up): key(K.up), .btn(.down): key(K.down), .btn(.left): key(K.left), .btn(.right): key(K.right),
    ]

    static let all: [Profile] = [
        Profile(
            id: "arrows",
            name: "Game · Arrow keys",
            summary: "Left stick & D-pad = arrows · RT = ↑ (gas) · LT = ↓ (brake) · A = Space · B = Shift · Start = Return · Back = Esc",
            left: .keys, right: .off,
            binds: dpadArrows.merging([
                .lUp: key(K.up), .lDown: key(K.down), .lLeft: key(K.left), .lRight: key(K.right),
                .rt: key(K.up), .lt: key(K.down),
                .btn(.a): key(K.space), .btn(.b): key(K.shift), .btn(.x): key(K.z), .btn(.y): key(K.x),
                .btn(.lb): key(K.q), .btn(.rb): key(K.e),
                .btn(.start): key(K.ret), .btn(.back): key(K.esc),
            ]) { $1 }
        ),
        Profile(
            id: "wasd",
            name: "Game · WASD + mouse",
            summary: "Left stick = WASD · right stick = mouse · RT = left click · LT = right click · A = Space · Start = Esc",
            left: .keys, right: .mouse,
            binds: dpadArrows.merging([
                .lUp: key(K.w), .lDown: key(K.s), .lLeft: key(K.a), .lRight: key(K.d),
                .rt: .click(.left), .lt: .click(.right),
                .btn(.a): key(K.space), .btn(.b): key(K.c), .btn(.x): key(K.r), .btn(.y): key(K.e),
                .btn(.lb): key(K.q), .btn(.rb): key(K.f), .btn(.ls): key(K.shift), .btn(.rs): key(K.v),
                .btn(.start): key(K.esc), .btn(.back): key(K.tab),
            ]) { $1 }
        ),
        Profile(
            id: "desktop",
            name: "Desktop · Mouse",
            summary: "Left stick = mouse · right stick = scroll · A = click · B = right click · LB/RB = back/forward",
            left: .mouse, right: .scroll,
            binds: dpadArrows.merging([
                .btn(.a): .click(.left), .btn(.b): .click(.right), .btn(.x): key(K.space),
                .btn(.lb): key(K.leftBracket, .maskCommand), .btn(.rb): key(K.rightBracket, .maskCommand),
                .btn(.start): key(K.ret), .btn(.back): key(K.esc),
            ]) { $1 }
        ),
    ]

    static func byID(_ id: String) -> Profile { all.first { $0.id == id } ?? all[0] }
}

/// Turns controller input into key presses, clicks, mouse movement and scrolling.
/// All methods run on the USB queue.
final class Mapper {
    private let queue: DispatchQueue
    private let src = CGEventSource(stateID: .hidSystemState)
    private let deadzone = 0.18
    private var enabled = false
    private var profile = Profiles.all[0]
    private var last = PadState()
    private var active = Set<Ctl>()
    private var keysDown: [CGKeyCode: CGEventFlags] = [:]
    private var clicksDown = Set<UInt32>()
    private var timer: DispatchSourceTimer?
    private var moveRest = CGPoint.zero
    private var scrollRest = CGPoint.zero

    private static let modifierFlag: [CGKeyCode: CGEventFlags] = [
        K.shift: .maskShift, K.control: .maskControl, K.option: .maskAlternate, K.cmd: .maskCommand,
    ]

    init(queue: DispatchQueue) { self.queue = queue }

    func configure(enabled: Bool, profile: Profile) {
        queue.async {
            self.releaseAll()
            self.enabled = enabled
            self.profile = profile
            self.apply(self.last)
        }
    }

    func apply(_ s: PadState) {
        last = s
        guard enabled else { return }

        var now = Set<Ctl>()
        for b in Btn.allCases where s.has(b) { now.insert(.btn(b)) }
        if isOn(.lt, s.lt) { now.insert(.lt) }
        if isOn(.rt, s.rt) { now.insert(.rt) }
        if profile.left == .keys { stick(&now, s.lx, s.ly, .lUp, .lDown, .lLeft, .lRight) }
        if profile.right == .keys { stick(&now, s.rx, s.ry, .rUp, .rDown, .rLeft, .rRight) }
        active = now

        var wantKeys: [CGKeyCode: CGEventFlags] = [:]
        var wantClicks = Set<UInt32>()
        for c in now {
            switch profile.binds[c] {
            case .key(let k, let f)?: wantKeys[k] = f
            case .click(let b)?: wantClicks.insert(b.rawValue)
            case nil: break
            }
        }
        for (k, f) in keysDown where wantKeys[k] == nil { postKey(k, f, down: false, held: wantKeys) }
        for (k, f) in wantKeys where keysDown[k] == nil { postKey(k, f, down: true, held: wantKeys) }
        keysDown = wantKeys
        for b in clicksDown.subtracting(wantClicks) { postClick(b, down: false) }
        for b in wantClicks.subtracting(clicksDown) { postClick(b, down: true) }
        clicksDown = wantClicks
        updateTimer()
    }

    // MARK: thresholds (with hysteresis so keys don't flicker)

    private func isOn(_ c: Ctl, _ v: Double) -> Bool { v > (active.contains(c) ? 0.3 : 0.5) }

    private func stick(_ set: inout Set<Ctl>, _ x: Double, _ y: Double, _ u: Ctl, _ d: Ctl, _ l: Ctl, _ r: Ctl) {
        if isOn(u, y) { set.insert(u) }
        if isOn(d, -y) { set.insert(d) }
        if isOn(l, -x) { set.insert(l) }
        if isOn(r, x) { set.insert(r) }
    }

    // MARK: events

    private func postKey(_ k: CGKeyCode, _ f: CGEventFlags, down: Bool, held: [CGKeyCode: CGEventFlags]) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: down) else { return }
        var mods: CGEventFlags = []
        for (hk, _) in held { if let m = Self.modifierFlag[hk] { mods.insert(m) } }
        if let m = Self.modifierFlag[k] {
            e.type = .flagsChanged
            if down { mods.insert(m) } else { mods.remove(m) }
            e.flags = mods
        } else {
            e.flags = mods.union(f)
        }
        e.post(tap: .cghidEventTap)
    }

    private func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private func postClick(_ raw: UInt32, down: Bool) {
        guard let b = CGMouseButton(rawValue: raw) else { return }
        let type: CGEventType
        switch b {
        case .left: type = down ? .leftMouseDown : .leftMouseUp
        case .right: type = down ? .rightMouseDown : .rightMouseUp
        default: type = down ? .otherMouseDown : .otherMouseUp
        }
        CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: cursor(), mouseButton: b)?.post(tap: .cghidEventTap)
    }

    private func needsTimer() -> Bool {
        guard enabled else { return false }
        func moving(_ use: StickUse, _ x: Double, _ y: Double) -> Bool {
            (use == .mouse || use == .scroll) && hypot(x, y) > deadzone
        }
        return moving(profile.left, last.lx, last.ly) || moving(profile.right, last.rx, last.ry)
    }

    private func updateTimer() {
        if needsTimer() {
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(8))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
        } else {
            timer?.cancel()
            timer = nil
        }
    }

    private func tick() {
        guard needsTimer() else { updateTimer(); return }
        var move = CGPoint.zero, scroll = CGPoint.zero
        for (use, x, y) in [(profile.left, last.lx, last.ly), (profile.right, last.rx, last.ry)] {
            let m = hypot(x, y)
            guard m > deadzone else { continue }
            let gain = pow(min(1, (m - deadzone) / (1 - deadzone)), 1.8) / m
            switch use {
            case .mouse: move.x += x * gain * 16; move.y -= y * gain * 16
            case .scroll: scroll.x -= x * gain * 7; scroll.y += y * gain * 7
            default: break
            }
        }
        if move != .zero { moveMouse(move) }
        if scroll != .zero { scrollBy(scroll) }
    }

    private func moveMouse(_ d: CGPoint) {
        moveRest.x += d.x; moveRest.y += d.y
        let dx = moveRest.x.rounded(.towardZero), dy = moveRest.y.rounded(.towardZero)
        moveRest.x -= dx; moveRest.y -= dy
        guard dx != 0 || dy != 0 else { return }
        let c = cursor()
        let p = clampToScreens(CGPoint(x: c.x + dx, y: c.y + dy))
        let type: CGEventType = clicksDown.contains(CGMouseButton.left.rawValue) ? .leftMouseDragged
            : clicksDown.contains(CGMouseButton.right.rawValue) ? .rightMouseDragged : .mouseMoved
        guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        e.post(tap: .cghidEventTap)
    }

    private func scrollBy(_ d: CGPoint) {
        scrollRest.x += d.x; scrollRest.y += d.y
        let sx = scrollRest.x.rounded(.towardZero), sy = scrollRest.y.rounded(.towardZero)
        scrollRest.x -= sx; scrollRest.y -= sy
        guard sx != 0 || sy != 0 else { return }
        CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2, wheel1: Int32(sy), wheel2: Int32(sx), wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    private func clampToScreens(_ p: CGPoint) -> CGPoint {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &n) == .success, n > 0 else { return p }
        let rects = ids.prefix(Int(n)).map { CGDisplayBounds($0) }
        if rects.contains(where: { $0.contains(p) }) { return p }
        // Snap to the nearest screen.
        let best = rects.min { dist($0, p) < dist($1, p) }!
        return CGPoint(x: min(max(p.x, best.minX), best.maxX - 1), y: min(max(p.y, best.minY), best.maxY - 1))
    }

    private func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    private func releaseAll() {
        for (k, f) in keysDown { postKey(k, f, down: false, held: [:]) }
        for b in clicksDown { postClick(b, down: false) }
        keysDown.removeAll()
        clicksDown.removeAll()
        active.removeAll()
        timer?.cancel()
        timer = nil
    }
}
