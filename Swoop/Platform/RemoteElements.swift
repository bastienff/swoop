import ApplicationServices
import Foundation

/// The ONLY product code that uses private Accessibility SPI (the one exception, ARCHITECTURE §2a).
///
/// An AX element of another process is addressed by a 20-byte "remote token":
/// `pid (4) | 0 (4) | magic "coco" (4) | AXUIElementID (8)`, little-endian. Element ids are assigned by the
/// target app when an element is first vended to any AX client, are small and dense, and stay valid for
/// the life of the element (F18–F21). Symbols are resolved with `dlsym`; if any is missing (a future
/// macOS), `isAvailable` is false and Swoop silently keeps its public-API-only behavior.
enum RemoteElements {
    private typealias CreateFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias TokenFn = @convention(c) (AXUIElement) -> Unmanaged<CFData>?
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private struct Symbols: @unchecked Sendable {
        let create: CreateFn
        let token: TokenFn
        let getWindow: GetWindowFn
    }

    private static let symbols: Symbols? = {
        guard let h = dlopen(nil, RTLD_NOW),
              let c = dlsym(h, "_AXUIElementCreateWithRemoteToken"),
              let t = dlsym(h, "_AXUIElementRemoteTokenCreate"),
              let w = dlsym(h, "_AXUIElementGetWindow") else { return nil }
        return Symbols(create: unsafeBitCast(c, to: CreateFn.self), token: unsafeBitCast(t, to: TokenFn.self),
                       getWindow: unsafeBitCast(w, to: GetWindowFn.self))
    }()

    static var isAvailable: Bool { symbols != nil }

    private static let tokenLength = 20
    private static let magic: UInt32 = 0x636f_636f // "coco"
    /// Per-element IPC timeout for recovered elements (a hung app must not stall a sweep).
    private static let elementTimeout: Float = 0.1

    /// The element's id inside its app. Local (no IPC): the token is serialized client-side.
    static func elementID(of e: AXElement) -> UInt64? {
        guard let s = symbols, let data = s.token(e.ref)?.takeRetainedValue(),
              CFDataGetLength(data) == tokenLength, let p = CFDataGetBytePtr(data) else { return nil }
        let raw = UnsafeRawPointer(p)
        guard raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self) == magic else { return nil }
        return raw.loadUnaligned(fromByteOffset: 12, as: UInt64.self)
    }

    /// Recreates the element with `id` in `pid`. Local; the element may be dead (check before use).
    static func element(pid: pid_t, id: UInt64) -> AXElement? {
        guard let s = symbols else { return nil }
        var bytes = token(pid: pid, id: id)
        guard let data = CFDataCreate(nil, &bytes, tokenLength),
              let ref = s.create(data)?.takeRetainedValue() else { return nil }
        AXUIElementSetMessagingTimeout(ref, elementTimeout)
        return AXElement(ref)
    }

    /// Window server number of the element's window (one IPC).
    static func windowNumber(of e: AXElement) -> CGWindowID? {
        guard let s = symbols else { return nil }
        var wid: CGWindowID = 0
        return s.getWindow(e.ref, &wid) == .success && wid != 0 ? wid : nil
    }

    /// Checks ids in `range` (ascending) until `deadline`, reporting each *window root* whose window
    /// number is not in `skipWindows`. Descendants resolve to their containing window's number, so
    /// elements of already-known windows cost one IPC and no role read. Returns the first unchecked id.
    static func sweepWindows(pid: pid_t, range: Range<UInt64>, skipWindows: Set<CGWindowID>, deadline: UInt64,
                             found: (UInt64, AXElement) -> Void) -> UInt64 {
        guard let s = symbols else { return range.upperBound }
        // One mutable buffer; only the id field is rewritten per candidate (the element parses the bytes,
        // it doesn't retain them).
        guard let data = CFDataCreateMutable(nil, tokenLength) else { return range.lowerBound }
        var initial = token(pid: pid, id: 0)
        CFDataAppendBytes(data, &initial, tokenLength)
        guard let bytes = CFDataGetMutableBytePtr(data) else { return range.lowerBound }
        var seen = skipWindows
        var id = range.lowerBound
        while id < range.upperBound {
            if id & 63 == 0, DispatchTime.now().uptimeNanoseconds >= deadline { return id }
            var v = id.littleEndian
            withUnsafeBytes(of: &v) { UnsafeMutableRawPointer(bytes + 12).copyMemory(from: $0.baseAddress!, byteCount: 8) }
            if let ref = s.create(data)?.takeRetainedValue() {
                AXUIElementSetMessagingTimeout(ref, elementTimeout)
                var wid: CGWindowID = 0
                if s.getWindow(ref, &wid) == .success, wid != 0, !seen.contains(wid) {
                    let e = AXElement(ref)
                    if e.role == (kAXWindowRole as String) {
                        seen.insert(wid)
                        found(id, e)
                    }
                }
            }
            id += 1
        }
        return id
    }

    private static func token(pid: pid_t, id: UInt64) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: tokenLength)
        withUnsafeBytes(of: pid.littleEndian) { for i in 0..<4 { bytes[i] = $0[i] } }
        withUnsafeBytes(of: magic.littleEndian) { for i in 0..<4 { bytes[8 + i] = $0[i] } }
        withUnsafeBytes(of: id.littleEndian) { for i in 0..<8 { bytes[12 + i] = $0[i] } }
        return bytes
    }
}
