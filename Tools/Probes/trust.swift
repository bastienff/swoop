import ApplicationServices
import AppKit
print("AX trusted:", AXIsProcessTrusted())
print("Screen capture preflight:", CGPreflightScreenCaptureAccess())
print("ListenEvent preflight:", CGPreflightListenEventAccess())
print("PostEvent preflight:", CGPreflightPostEventAccess())
for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular {
  print(a.processIdentifier, a.bundleIdentifier ?? "-", a.localizedName ?? "-")
}
