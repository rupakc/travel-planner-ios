import Foundation
import os

/// Cold start: process start (`sysctl` `KERN_PROC_PID` `p_starttime`) to the first rendered frame.
public enum ColdStart {
    private static let marked = OSAllocatedUnfairLock(initialState: false)

    /// The first call emits `perf{metric: cold_start, value: ms, route: "/"}`; later calls do nothing.
    public static func markFirstFrame() {
        let first = marked.withLock { done -> Bool in
            defer { done = true }
            return !done
        }
        guard first, let ms = elapsedMilliseconds(now: Date()) else { return }
        Telemetry.shared.track(.perf(metric: .coldStart, value: ms, route: "/"))
    }

    static func processStart() -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    static func elapsedMilliseconds(now: Date) -> Double? {
        guard let start = processStart() else { return nil }
        let ms = now.timeIntervalSince(start) * 1000
        return ms >= 0 ? ms.rounded() : nil
    }
}
