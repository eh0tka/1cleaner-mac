import Foundation

/// Simulator devices and runtimes, read from `xcrun simctl` and removed by it (never through the Trash).
struct SimulatorScanner: Scanner {
    static let xcrun = "/usr/bin/xcrun"

    var categories: [CategoryID] { [.simulators] }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        [.simulators: await scanSimulators()]
    }

    /// True when full Xcode is selected; `xcrun` alone would offer to install the Command Line Tools.
    static func hasXcode() async -> Bool {
        guard let output = try? await ProcessRunner.run("/usr/bin/xcode-select", ["-p"], timeout: .seconds(10)),
              output.succeeded else { return false }
        let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasSuffix(".app/Contents/Developer") && FileInfo.exists(path)
    }

    private func scanSimulators() async -> ScanOutput {
        guard await Self.hasXcode() else {
            return ScanOutput(notes: [String(localized: "Xcode isn't installed, so there are no simulators to manage.",
                                             comment: "Note in the Simulators category")])
        }
        var output = ScanOutput()
        var devicesByRuntime: [String: Int] = [:]
        var runningRuntimes = Set<String>()

        do {
            let result = try await ProcessRunner.run(Self.xcrun, ["simctl", "list", "devices", "--json"], timeout: .seconds(60))
            guard result.succeeded else { throw ProcessRunner.Failure.launch(result.errorMessage) }
            let list = try JSONDecoder().decode(DeviceList.self, from: Data(result.stdout.utf8))
            for (runtime, devices) in list.devices {
                devicesByRuntime[runtime, default: 0] += devices.count
                if devices.contains(where: { $0.state != "Shutdown" }) { runningRuntimes.insert(runtime) }
                for device in devices {
                    output.items.append(item(for: device, runtime: runtime))
                }
            }
        } catch {
            output.notes.append(String(localized: "Couldn't list simulator devices: \(error.localizedDescription)",
                                       comment: "Note in the Simulators category; %@ is the error message"))
        }

        if let result = try? await ProcessRunner.run(Self.xcrun, ["simctl", "runtime", "list", "--json"], timeout: .seconds(60)),
           result.succeeded,
           let runtimes = try? JSONDecoder().decode([String: Runtime].self, from: Data(result.stdout.utf8)) {
            for runtime in runtimes.values {
                output.items.append(item(for: runtime, deviceCount: devicesByRuntime[runtime.runtimeIdentifier ?? ""] ?? 0,
                                         running: runningRuntimes.contains(runtime.runtimeIdentifier ?? "")))
            }
        }
        output.items.sort { $0.size > $1.size }
        return output
    }

    private func item(for device: Device, runtime: String) -> CleanupItem {
        var size = device.dataPathSize ?? 0
        if device.dataPathSize == nil, let dataPath = device.dataPath {
            size = FileSizer.measure((dataPath as NSString).deletingLastPathComponent).bytes
        }
        let lastUsed = device.lastUsedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        var detail = Self.runtimeName(runtime)
        if device.isAvailable == false {
            let reason = device.availabilityError
                ?? String(localized: "runtime is missing", comment: "Why a simulator device can't run, in parentheses")
            detail += " · " + String(localized: "can't run: its iOS is gone (\(reason))",
                                     comment: "Fact in a simulator device's detail line; %@ is the reason from Xcode (English)")
        } else {
            detail += " · " + (lastUsed.map {
                String(localized: "used \($0.relativeDescription)",
                       comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
            } ?? String(localized: "never used", comment: "Fact in a simulator's detail line"))
            detail += " · " + String(localized: "removing it keeps \(Self.runtimeName(runtime))",
                                     comment: "Fact in a simulator device's detail line; %@ is a runtime like iOS 17.5")
        }
        return CleanupItem(
            id: "sim:device:\(device.udid)",
            category: .simulators,
            title: device.name,
            badge: device.isAvailable == false
                ? String(localized: "Unavailable", comment: "Badge of a simulator device whose iOS version is gone")
                : String(localized: "Device", comment: "Badge of a simulator device"),
            detail: detail,
            size: size,
            removal: .simulatorDevice(udid: device.udid, lastUsed: device.lastUsedAt),
            lockedReason: device.state == "Shutdown" ? nil
                : String(localized: "Running. Shut it down to remove it.", comment: "Why a running simulator device can't be selected"),
            date: lastUsed,
            safetyLevel: device.isAvailable == false ? .safe : nil
        )
    }

    private func item(for runtime: Runtime, deviceCount: Int, running: Bool) -> CleanupItem {
        let platform = runtime.runtimeIdentifier.map { Self.runtimeName($0) }
            ?? String(localized: "Simulator \(runtime.version ?? "")", comment: "Simulator runtime name; %@ is its version")
        let lastUsed = runtime.lastUsedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        var detail = String(localized: "Build \(runtime.build ?? "?")", comment: "Simulator runtime detail; %@ is a build number like 21F79")
        if let lastUsed {
            detail += " · " + String(localized: "used \(lastUsed.relativeDescription)",
                                     comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
        }
        detail += " · " + (deviceCount == 0
            ? String(localized: "no devices use it", comment: "Fact in a simulator runtime's detail line")
            : String(localized: """
                \(deviceCount) devices stop working without it; getting it back is a \((runtime.sizeBytes ?? 0).formattedBytes) download
                """, comment: "Fact in a simulator runtime's detail line; %lld is the number of devices, %@ a download size"))
        return CleanupItem(
            id: "sim:runtime:\(runtime.identifier)",
            category: .simulators,
            title: String(localized: "\(platform) runtime", comment: "Simulator runtime row title; %@ is a platform like iOS 17.5"),
            badge: String(localized: "Runtime", comment: "Badge of a simulator runtime"),
            detail: detail,
            size: runtime.sizeBytes ?? 0,
            removal: .simulatorRuntime(id: runtime.identifier),
            // Removing a runtime shuts down the simulators running on it.
            lockedReason: runtime.deletable != true
                ? String(localized: "Installed with Xcode; remove it in Xcode Settings › Components.",
                         comment: "Why a simulator runtime can't be selected; Xcode Settings › Components is Xcode's menu path")
                : running ? Self.runtimeRunningReason : nil,
            date: lastUsed
        )
    }

    static var runtimeRunningReason: String {
        String(localized: "A simulator on it is running. Shut it down to remove it.",
               comment: "Why a simulator runtime can't be selected or removed")
    }

    /// Right before removal: the device or the runtime (by its install id) has a simulator running now. Unknown
    /// (simctl failed) counts as running.
    static func isRunning(device udid: String? = nil, runtime installID: String? = nil) async -> Bool {
        guard let result = try? await ProcessRunner.run(xcrun, ["simctl", "list", "devices", "--json"], timeout: .seconds(60)),
              result.succeeded, let list = try? JSONDecoder().decode(DeviceList.self, from: Data(result.stdout.utf8))
        else { return true }
        if let udid {
            return list.devices.values.joined().contains { $0.udid == udid && $0.state != "Shutdown" }
        }
        guard let installID,
              let runtimes = try? await ProcessRunner.run(xcrun, ["simctl", "runtime", "list", "--json"], timeout: .seconds(60)),
              runtimes.succeeded,
              let installed = try? JSONDecoder().decode([String: Runtime].self, from: Data(runtimes.stdout.utf8)),
              let runtime = installed.values.first(where: { $0.identifier == installID })?.runtimeIdentifier
        else { return true }
        return list.devices[runtime]?.contains { $0.state != "Shutdown" } ?? false
    }

    /// Right before removal: the device was used since the scan (simctl's "last used" mark moved), is gone, or
    /// simctl couldn't tell.
    static func usedSinceScan(device udid: String, lastUsed: String?) async -> Bool {
        guard let result = try? await ProcessRunner.run(xcrun, ["simctl", "list", "devices", "--json"], timeout: .seconds(60)),
              result.succeeded, let list = try? JSONDecoder().decode(DeviceList.self, from: Data(result.stdout.utf8)),
              let device = list.devices.values.joined().first(where: { $0.udid == udid })
        else { return true }
        return device.lastUsedAt != lastUsed
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-17-5" → "iOS 17.5".
    static func runtimeName(_ identifier: String) -> String {
        guard let last = identifier.split(separator: ".").last else { return identifier }
        let parts = last.split(separator: "-")
        guard let platform = parts.first else { return String(last) }
        return platform + " " + parts.dropFirst().joined(separator: ".")
    }

    private struct DeviceList: Decodable {
        let devices: [String: [Device]]
    }

    private struct Device: Decodable {
        let udid: String
        let name: String
        let state: String?
        let isAvailable: Bool?
        let availabilityError: String?
        let dataPath: String?
        let dataPathSize: Int64?
        let lastUsedAt: String?
    }

    private struct Runtime: Decodable {
        let identifier: String
        let version: String?
        let build: String?
        let runtimeIdentifier: String?
        let sizeBytes: Int64?
        let deletable: Bool?
        let lastUsedAt: String?
    }
}
