import Darwin
import SwiftUI

@main
struct DLChatApp: App {
    @UIApplicationDelegateAdaptor(HygieneAppDelegate.self) private var appDelegate
    private let launch = Launch()

    init() { LaunchTiming.mark("app.init") }

    var body: some Scene {
        WindowGroup {
            RootView(start: launch.screen)
        }
    }
}

/// `-launch-timing`: prints how long after the process started each step of launch and unlock happened,
/// for measuring how fast DLChat opens. Off unless that argument is passed; it prints step names and
/// times only, never content.
enum LaunchTiming {
    static let on = ProcessInfo.processInfo.arguments.contains("-launch-timing")

    /// The process start time from the kernel, so time spent before `main` counts too.
    private static let start: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let t = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000)
    }()

    static func mark(_ step: String) {
        guard on else { return }
        let ms = Int((Date().timeIntervalSince(start) * 1000).rounded())
        print("[launch] \(step) +\(ms)ms")
        fflush(stdout)
    }
}
