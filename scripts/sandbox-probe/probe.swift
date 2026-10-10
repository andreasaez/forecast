// Tries what an attacker would want a sandboxed Forecast to do, and reports what macOS allowed.
// Built and signed twice by scripts/sandbox-probe.sh: unprotected (control) and with Forecast's entitlements.
// Network traffic only goes to a listener on 127.0.0.1. Nothing leaves the machine.
import CoreServices
import Foundation

/// One line per check: ALLOWED or BLOCKED, the check, and optional detail, separated by tabs.
func report(_ name: String, _ allowed: Bool, _ detail: String = "") {
    print("\(allowed ? "ALLOWED" : "BLOCKED")\t\(name)\t\(detail)")
}
let port = in_port_t(CommandLine.arguments.count > 1 ? UInt16(CommandLine.arguments[1]) ?? 54321 : 54321)

// Network: a raw socket, then an ordinary web request.
var address = sockaddr_in()
address.sin_family = sa_family_t(AF_INET)
address.sin_port = port.bigEndian
address.sin_addr.s_addr = inet_addr("127.0.0.1")
let fd = socket(AF_INET, SOCK_STREAM, 0)
let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
}
report("network: open a connection", fd >= 0 && connected == 0)
close(fd)

let done = DispatchSemaphore(value: 0)
var responded = false
URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:\(port)/")!) { _, response, _ in
    responded = response != nil
    done.signal()
}.resume()
_ = done.wait(timeout: .now() + 5)
report("network: make a web request", responded)

// Files outside the sandbox, including the calendar database itself.
let home = "/Users/" + NSUserName()
report("files: list ~/Documents", (try? FileManager.default.contentsOfDirectory(atPath: home + "/Documents")) != nil)
report("files: read the Calendar database directly",
       (try? FileManager.default.contentsOfDirectory(atPath: home + "/Library/Group Containers/group.com.apple.calendar")) != nil)
let target = home + "/Desktop/.forecast-probe-\(getpid())"
let wrote = FileManager.default.createFile(atPath: target, contents: Data("x".utf8))
if wrote { try? FileManager.default.removeItem(atPath: target) }
report("files: write to the Desktop", wrote)

// A child process inherits the sandbox: can it reach the network?
let curl = Process()
curl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
curl.arguments = ["-s", "--noproxy", "*", "-o", "/dev/null", "-m", "5", "-w", "%{http_code}", "http://127.0.0.1:\(port)/"]
// Launch curl without the injected library, or (with SIP off) it would print into curl's output.
curl.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") }
let pipe = Pipe()
curl.standardOutput = pipe
curl.standardError = FileHandle.nullDevice
var childReached = false
if (try? curl.run()) != nil {
    curl.waitUntilExit()
    childReached = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) == "200"
}
report("network: through a child process", childReached, "curl")

// Apple Events: ask Finder for data. Never prompts: macOS answers without asking you.
let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
                                   targetDescriptor: finder, returnID: AEReturnID(kAutoGenerateReturnID),
                                   transactionID: AETransactionID(kAnyTransactionID))
var reply = AppleEvent()
let mode = AESendMode(kAEWaitReply | kAENeverInteract | kAEDoNotPromptForUserConsent)
let status = AESendMessage(event.aeDesc!, &reply, mode, 300)
AEDisposeDesc(&reply)
switch Int(status) {
case Int(errAEEventNotPermitted):
    report("apple events: send to Finder", false, "not permitted (\(status))")
case Int(procNotFound):
    // Finder is running for the control; a sandboxed process can't even find it.
    report("apple events: send to Finder", false, "couldn't reach Finder (\(status))")
case Int(errAEEventWouldRequireUserConsent):
    report("apple events: send to Finder", true, "allowed once you consent (\(status))")
default:
    report("apple events: send to Finder", true, "delivered (\(status))")
}
