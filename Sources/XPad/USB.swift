import Foundation
import IOKit
import IOKit.usb
import IOUSBHost

private let kMsgTerminated: UInt32 = 0xE000_0010          // kIOMessageServiceIsTerminated
private let kReturnAborted = Int32(bitPattern: 0xE000_02EB) // kIOReturnAborted

/// Finds an Xbox 360-style (XInput) controller on USB and streams its input.
/// macOS has no driver for these, so XPad talks to the device directly from user space.
final class USBPad {
    var onState: ((PadState) -> Void)?
    var onDevice: ((String?) -> Void)?
    /// Name of the app currently holding the controller, or nil.
    var onBusy: ((String?) -> Void)?
    let queue = DispatchQueue(label: "xpad.usb", qos: .userInteractive)

    private var port: IONotificationPortRef?
    private var devIter: io_iterator_t = 0
    private var ifIter: io_iterator_t = 0
    private var hosts: [IOUSBHostDevice] = []
    private var iface: IOUSBHostInterface?
    private var pipeIn: IOUSBHostPipe?
    private var buffer: NSMutableData?
    private var paused = false
    private var retryScheduled = false
    private var sawBusy = false

    func start() { queue.async { self.setup() } }

    func setPaused(_ p: Bool) {
        queue.async {
            guard p != self.paused else { return }
            self.paused = p
            if p { self.releaseAll() } else { self.rescan() }
        }
    }

    // MARK: discovery

    private func setup() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, queue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"), { ref, it in
            Unmanaged<USBPad>.fromOpaque(ref!).takeUnretainedValue().devicesArrived(it)
        }, ctx, &devIter)
        devicesArrived(devIter)
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostInterface"), { ref, it in
            Unmanaged<USBPad>.fromOpaque(ref!).takeUnretainedValue().interfacesArrived(it)
        }, ctx, &ifIter)
        interfacesArrived(ifIter)
    }

    private func rescan() {
        sawBusy = false
        defer { if !sawBusy { onBusy?(nil) } }
        var it: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &it) == KERN_SUCCESS {
            devicesArrived(it); IOObjectRelease(it)
        }
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostInterface"), &it) == KERN_SUCCESS {
            interfacesArrived(it); IOObjectRelease(it)
        }
    }

    private func each(_ it: io_iterator_t, _ body: (io_service_t) -> Void) {
        var s = IOIteratorNext(it)
        while s != 0 {
            body(s)
            IOObjectRelease(s)
            s = IOIteratorNext(it)
        }
    }

    private func intProp(_ s: io_service_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
    }

    private func strProp(_ s: io_service_t, _ key: String) -> String? {
        let opts = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        return IORegistryEntrySearchCFProperty(s, kIOServicePlane, key as CFString, kCFAllocatorDefault, opts) as? String
    }

    /// Vendor-specific devices are left unconfigured by macOS. If one carries an XInput
    /// interface, configure it so the interface appears.
    private func devicesArrived(_ it: io_iterator_t) {
        each(it) { s in
            guard !paused, intProp(s, "bDeviceClass") == 0xFF, !hasInterfaces(s) else { return }
            configureIfXInput(s)
        }
    }

    private func hasInterfaces(_ s: io_service_t) -> Bool {
        var child: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(s, kIOServicePlane, &child) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(child) }
        var found = false
        each(child) { c in if IOObjectConformsTo(c, "IOUSBHostInterface") != 0 { found = true } }
        return found
    }

    private func configureIfXInput(_ s: io_service_t) {
        do {
            let dev = try IOUSBHostDevice(__ioService: s, options: [], queue: queue) { [weak self] obj, type, _ in
                guard type == kMsgTerminated else { return }
                self?.hosts.removeAll { $0 === obj }
                obj.destroy()
            }
            let cfg = try dev.configurationDescriptor(with: 0)
            guard Self.xinputInterface(in: cfg) != nil else { dev.destroy(); return }
            try dev.__configure(withValue: Int(cfg.pointee.bConfigurationValue), matchInterfaces: true)
            hosts.append(dev)
        } catch {
            // Device busy or not ours: ignore.
        }
    }

    private func interfacesArrived(_ it: io_iterator_t) {
        each(it) { s in
            guard !paused, iface == nil,
                  intProp(s, "bInterfaceClass") == 0xFF,
                  intProp(s, "bInterfaceSubClass") == 0x5D,
                  intProp(s, "bInterfaceProtocol") == 0x01 else { return }
            if let owner = IORegistryEntryCreateCFProperty(s, "UsbExclusiveOwner" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String {
                // e.g. "pid 1285, Google Chrome"
                sawBusy = true
                onBusy?(owner.components(separatedBy: ", ").last ?? owner)
                retrySoon()
                return
            }
            open(s)
        }
    }

    // MARK: descriptors

    /// Walks a configuration descriptor. Returns (interfaceNumber, inEndpoint, outEndpoint) of the first XInput interface.
    static func xinputInterface(in cfg: UnsafePointer<IOUSBConfigurationDescriptor>, number: Int? = nil) -> (Int, Int?, Int?)? {
        let total = Int(UInt16(littleEndian: cfg.pointee.wTotalLength))
        let b = UnsafeRawPointer(cfg).assumingMemoryBound(to: UInt8.self)
        var i = 0
        var current: Int? = nil
        var inEP: Int? = nil, outEP: Int? = nil
        while i + 2 <= total {
            let len = Int(b[i]), type = b[i + 1]
            if len < 2 || i + len > total { break }
            if type == 4, len >= 9 { // interface
                if current != nil { break }
                let num = Int(b[i + 2]), alt = b[i + 3]
                if alt == 0, b[i + 5] == 0xFF, b[i + 6] == 0x5D, b[i + 7] == 0x01, number == nil || number == num {
                    current = num
                }
            } else if type == 5, len >= 7, current != nil { // endpoint
                let addr = Int(b[i + 2]), attr = b[i + 3] & 0x3
                if attr == 3 {
                    if addr & 0x80 != 0 { inEP = inEP ?? addr } else { outEP = outEP ?? addr }
                }
            }
            i += len
        }
        guard let n = current else { return nil }
        return (n, inEP, outEP)
    }

    // MARK: reading

    private func open(_ s: io_service_t) {
        do {
            let itf = try IOUSBHostInterface(__ioService: s, options: [], queue: queue) { [weak self] _, type, _ in
                if type == kMsgTerminated { self?.closeInterface() }
            }
            let number = Int(itf.interfaceDescriptor.pointee.bInterfaceNumber)
            guard let (_, inEP, outEP) = Self.xinputInterface(in: itf.configurationDescriptor, number: number),
                  let inAddr = inEP else { itf.destroy(); return }
            let pipe = try itf.copyPipe(withAddress: inAddr)
            iface = itf
            pipeIn = pipe

            // Some third-party pads only start reporting after this vendor request (same as Linux xpad).
            let req = IOUSBDeviceRequest(bmRequestType: 0xC1, bRequest: 0x01, wValue: 0x0100, wIndex: UInt16(number), wLength: 20)
            if let scratch = NSMutableData(length: 20) {
                try? itf.__send(req, data: scratch, bytesTransferred: nil, completionTimeout: 1)
            }
            // Player 1 LED.
            if let outAddr = outEP, let out = try? itf.copyPipe(withAddress: outAddr) {
                let led = NSMutableData(bytes: [UInt8(0x01), 0x03, 0x06], length: 3)
                try? out.__sendIORequest(with: led, bytesTransferred: nil, completionTimeout: 1)
            }

            buffer = try itf.ioData(withCapacity: 32)
            onBusy?(nil)
            onDevice?(strProp(s, "USB Product Name") ?? "Controller")
            read()
        } catch {
            closeInterface()
        }
    }

    private func read() {
        guard let pipe = pipeIn, let buf = buffer else { return }
        do {
            try pipe.enqueueIORequest(with: buf, completionTimeout: 0) { [weak self] status, count in
                self?.completed(status, count)
            }
        } catch {
            closeInterface()
        }
    }

    private func completed(_ status: IOReturn, _ count: Int) {
        guard pipeIn != nil else { return }
        if status == kIOReturnSuccess, let buf = buffer {
            let raw = UnsafeRawBufferPointer(start: buf.bytes, count: min(count, buf.length))
            if let s = XInput.parse(raw) { onState?(s) }
            read()
        } else if status != kReturnAborted {
            closeInterface()
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, !self.paused, self.iface == nil else { return }
                self.rescan()
            }
        }
    }

    private func retrySoon() {
        guard !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            if !self.paused && self.iface == nil { self.rescan() }
        }
    }

    private func closeInterface() {
        let had = iface != nil
        pipeIn = nil
        buffer = nil
        iface?.destroy()
        iface = nil
        if had {
            onState?(PadState())
            onDevice?(nil)
        }
    }

    private func releaseAll() {
        closeInterface()
        onBusy?(nil)
        hosts.forEach { $0.destroy() }
        hosts.removeAll()
    }
}
