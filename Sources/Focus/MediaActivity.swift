import AppKit
import IOKit.ps
import IOKit.pwr_mgt

/// 判断有没有别的 App 正在阻止屏幕休眠。浏览器和播放器播视频、视频会议时都会这样做，
/// 这时用户很可能正在电脑上看网课或开会，不该自动模糊。
enum MediaActivity {
    private static let displayAssertionTypes: Set<String> = [
        kIOPMAssertPreventUserIdleDisplaySleep as String,
        "NoDisplaySleepAssertion",
    ]

    /// 返回正在让屏幕保持常亮的 App 名称；没有则返回 nil
    static func appKeepingDisplayAwake() -> String? {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        for (pid, assertions) in byProcess where pid.int32Value != ownPID {
            let keepsDisplayAwake = assertions.contains { assertion in
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String else { return false }
                return displayAssertionTypes.contains(type)
            }
            guard keepsDisplayAwake else { continue }
            // 只认带界面的 App，系统后台进程（比如 caffeinate 之外的守护进程）不算
            if let app = NSRunningApplication(processIdentifier: pid.int32Value), app.activationPolicy == .regular {
                return app.localizedName ?? "其他 App"
            }
        }
        return nil
    }
}

enum Battery {
    /// 正在用电池且电量低于 20%
    static var isLow: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            if Double(current) / Double(max) < 0.2 { return true }
        }
        return false
    }
}
