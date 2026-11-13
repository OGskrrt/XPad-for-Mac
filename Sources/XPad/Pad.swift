import Foundation

/// Buttons in the order XPad stores them.
enum Btn: Int, CaseIterable {
    case a, b, x, y, lb, rb, back, start, ls, rs, up, down, left, right, home
}

/// One snapshot of the controller. Sticks are -1...1, up is +1. Triggers are 0...1.
struct PadState: Equatable {
    var buttons: UInt32 = 0
    var lt = 0.0, rt = 0.0
    var lx = 0.0, ly = 0.0, rx = 0.0, ry = 0.0

    func has(_ b: Btn) -> Bool { buttons & (1 << UInt32(b.rawValue)) != 0 }
}

/// Xbox 360 (XInput) USB input report parser.
enum XInput {
    static func parse(_ p: UnsafeRawBufferPointer) -> PadState? {
        guard p.count >= 14, p[0] == 0x00, p[1] >= 0x14 else { return nil }
        let lo = p[2], hi = p[3]
        func bit(_ v: UInt8, _ n: UInt8) -> Bool { (v >> n) & 1 == 1 }
        let pairs: [(Bool, Btn)] = [
            (bit(hi, 4), .a), (bit(hi, 5), .b), (bit(hi, 6), .x), (bit(hi, 7), .y),
            (bit(hi, 0), .lb), (bit(hi, 1), .rb), (bit(hi, 2), .home),
            (bit(lo, 5), .back), (bit(lo, 4), .start), (bit(lo, 6), .ls), (bit(lo, 7), .rs),
            (bit(lo, 0), .up), (bit(lo, 1), .down), (bit(lo, 2), .left), (bit(lo, 3), .right),
        ]
        var s = PadState()
        for (on, b) in pairs where on { s.buttons |= 1 << UInt32(b.rawValue) }
        s.lt = Double(p[4]) / 255
        s.rt = Double(p[5]) / 255
        func axis(_ o: Int) -> Double {
            let raw = Int16(bitPattern: UInt16(p[o]) | UInt16(p[o + 1]) << 8)
            return max(-1, Double(raw) / 32767)
        }
        s.lx = axis(6); s.ly = axis(8); s.rx = axis(10); s.ry = axis(12)
        return s
    }
}
