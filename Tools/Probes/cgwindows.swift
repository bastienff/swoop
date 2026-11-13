import CoreGraphics
import Foundation
let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as! [[String: Any]]
var counts: [String: (on: Int, off: Int)] = [:]
for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
  let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
  let on = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
  let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
  let h = b["Height"] as? Double ?? 0, wd = b["Width"] as? Double ?? 0
  if wd < 50 || h < 50 { continue }
  var c = counts[owner] ?? (0,0); if on { c.on += 1 } else { c.off += 1 }; counts[owner] = c
  print(w[kCGWindowNumber as String]!, owner, "onscreen=\(on)", "name=\(w[kCGWindowName as String] ?? "<nil>")", "alpha=\(w[kCGWindowAlpha as String]!)", "\(Int(wd))x\(Int(h))")
}
print("---"); for (k,v) in counts.sorted(by: {$0.key<$1.key}) { print(k, "on:", v.on, "off:", v.off) }
