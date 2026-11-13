import ApplicationServices
import Foundation

/// Sendable wrapper over an immutable `AXUIElement` reference.
/// AX references are thread-safe CF objects; all calls are synchronous IPC bounded by the
/// element's messaging timeout.
struct AXElement: @unchecked Sendable, Hashable {
    let ref: AXUIElement

    init(_ ref: AXUIElement) { self.ref = ref }

    static func application(_ pid: pid_t, timeout: Float = 0.3) -> AXElement {
        let e = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(e, timeout)
        return AXElement(e)
    }

    static func == (a: AXElement, b: AXElement) -> Bool { CFEqual(a.ref, b.ref) }
    func hash(into h: inout Hasher) { h.combine(CFHash(ref)) }

    // MARK: Attributes

    func raw(_ attribute: String) -> (AXError, AnyObject?) {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(ref, attribute as CFString, &value)
        return (err, value)
    }

    func value(_ attribute: String) -> AnyObject? {
        let (err, v) = raw(attribute)
        return err == .success ? v : nil
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }
    func bool(_ attribute: String) -> Bool? { (value(attribute) as? NSNumber)?.boolValue }
    func int(_ attribute: String) -> Int? { (value(attribute) as? NSNumber)?.intValue }

    func element(_ attribute: String) -> AXElement? {
        guard let v = value(attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return AXElement(v as! AXUIElement)
    }

    func elements(_ attribute: String) -> [AXElement] {
        guard let arr = value(attribute) as? [AnyObject] else { return [] }
        return arr.compactMap { v in
            CFGetTypeID(v) == AXUIElementGetTypeID() ? AXElement(v as! AXUIElement) : nil
        }
    }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var title: String? { string(kAXTitleAttribute) }
    var children: [AXElement] { elements(kAXChildrenAttribute) }

    /// Global frame (top-left origin, same space as CG window bounds).
    var frame: CGRect? {
        guard let p = value(kAXPositionAttribute), let z = value(kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(z) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(z as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    var pid: pid_t? {
        var p: pid_t = 0
        return AXUIElementGetPid(ref, &p) == .success ? p : nil
    }

    /// False when the element is gone (window closed / app quit).
    var isAlive: Bool {
        let (err, _) = raw(kAXRoleAttribute)
        return err != .invalidUIElement && err != .cannotComplete
    }

    // MARK: Actions

    @discardableResult
    func set(_ attribute: String, _ value: AnyObject) -> AXError {
        AXUIElementSetAttributeValue(ref, attribute as CFString, value)
    }

    @discardableResult
    func perform(_ action: String) -> AXError {
        AXUIElementPerformAction(ref, action as CFString)
    }
}

extension AXElement: CustomDebugStringConvertible {
    var debugDescription: String { "AX(\(role ?? "?") \"\(title ?? "")\")" }
}
