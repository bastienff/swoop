// Sends a debug command to a running DEBUG build of Swoop.
// Usage: swctl <command> [argument...]   e.g. swctl show; swctl type heron; swctl dump /tmp/x.txt
import Foundation
let args = CommandLine.arguments.dropFirst().joined(separator: " ")
DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.bastienff.swoop.debug"), object: args, userInfo: nil, deliverImmediately: true)
