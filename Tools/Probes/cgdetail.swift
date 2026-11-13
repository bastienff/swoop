import CoreGraphics
let ids: Set<UInt32> = Set(CommandLine.arguments.dropFirst().compactMap { UInt32($0) })
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for (i, w) in list.enumerated() where ids.contains(w[kCGWindowNumber as String] as! UInt32) {
  print("z=\(i)", w.filter { $0.key != "kCGWindowBounds" }.sorted { $0.key < $1.key }.map { "\($0.key.replacingOccurrences(of: "kCGWindow", with: ""))=\($0.value)" }.joined(separator: " "))
}
