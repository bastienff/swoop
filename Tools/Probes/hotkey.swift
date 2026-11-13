import Carbon
var ref: EventHotKeyRef?
func t(_ mods: Int, _ label: String) {
  let s = RegisterEventHotKey(UInt32(kVK_Tab), UInt32(mods), EventHotKeyID(signature: 0x53575443, id: 1), GetApplicationEventTarget(), 0, &ref)
  print(label, "status:", s); if s == noErr { UnregisterEventHotKey(ref) }
}
t(optionKey, "⌥Tab"); t(optionKey|shiftKey, "⌥⇧Tab"); t(controlKey|optionKey, "⌃⌥Tab"); t(cmdKey|optionKey, "⌘⌥Tab"); t(0, "bare Tab")
