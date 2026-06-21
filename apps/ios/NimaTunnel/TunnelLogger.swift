import Foundation
import os

/// Writes log lines to both:
/// 1. Apple's unified logging system (streamable via `log stream` over USB)
/// 2. A shared file in the app group container (viewable in-app)
final class TunnelLogger {

    static let shared = TunnelLogger()

    private let fileURL: URL?
    private let lock = NSLock()
    private var bufferedLines: [String] = []
    private var bufferedBytes = 0
    private var lastProtectionApplyAt = Date.distantPast
    private var breadcrumbLastLoggedAt: [String: Date] = [:]
    private lazy var flushTimer: DispatchSourceTimer = {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(
            deadline: .now() + NimaConstants.tunnelLogFlushIntervalSeconds,
            repeating: NimaConstants.tunnelLogFlushIntervalSeconds
        )
        timer.setEventHandler { [weak self] in
            self?.flushBufferedLines()
        }
        timer.resume()
        return timer
    }()

    // os.Logger for real-time streaming to Mac via USB
    private static let osLog = Logger(
        subsystem: NimaConstants.logSubsystem,
        category: "tunnel"
    )

    // Separate logger for per-connection data (filterable)
    static let connectionLog = Logger(
        subsystem: NimaConstants.logSubsystem,
        category: "connection"
    )

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private init() {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NimaConstants.appGroupID) {
            self.fileURL = container.appendingPathComponent(NimaConstants.logFileName)
        } else {
            self.fileURL = nil
        }
        _ = flushTimer
    }

    func log(_ message: String, function: String = #function) {
        let timestamp = Self.dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(function)] \(message)\n"

        // Stream to Mac via USB (Console.app / `log stream`)
        Self.osLog.log("[\(function, privacy: .public)] \(message, privacy: .public)")

        guard let fileURL = fileURL else { return }

        lock.lock()
        defer { lock.unlock() }
        bufferedLines.append(line)
        bufferedBytes += line.lengthOfBytes(using: .utf8)
        if bufferedLines.count >= NimaConstants.tunnelLogFlushLineThreshold ||
            bufferedBytes >= NimaConstants.tunnelLogFlushByteThreshold {
            flushBufferedLinesLocked()
        }
    }

    func logAndFlush(_ message: String, function: String = #function) {
        log(message, function: function)
        flush()
    }

    func breadcrumb(_ name: String, details: String, minInterval: TimeInterval = 5.0, function: String = #function) {
        let now = Date()
        lock.lock()
        let last = breadcrumbLastLoggedAt[name] ?? .distantPast
        if now.timeIntervalSince(last) < minInterval {
            lock.unlock()
            return
        }
        breadcrumbLastLoggedAt[name] = now
        lock.unlock()

        if let defaults = UserDefaults(suiteName: NimaConstants.appGroupID) {
            defaults.set(name, forKey: NimaConstants.vpnLifecycleLastBreadcrumbKey)
            defaults.set(now.timeIntervalSince1970, forKey: NimaConstants.vpnLifecycleLastBreadcrumbTSKey)
            defaults.set(details, forKey: NimaConstants.vpnLifecycleLastBreadcrumbDetailsKey)
        }
        log("BREADCRUMB name=\(name) \(details)", function: function)
    }

    /// Log connection-level data to the "connection" category for filtering
    func logConnection(_ message: String) {
        #if DEBUG
        Self.connectionLog.log("\(message, privacy: .public)")
        // Also write to file for in-app viewing
        log(message)
        #endif
    }

    func clear() {
        log("========== NEW TUNNEL SESSION ==========")
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        flushBufferedLinesLocked()
    }

    static func readLog() -> String {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NimaConstants.appGroupID) else {
            return "(no app group container)"
        }
        let fileURL = container.appendingPathComponent(NimaConstants.logFileName)
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "(no logs yet)"
    }

    // MARK: - Private

    private func rotateLog(at fileURL: URL) {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n")
        let keepFrom = lines.count / 2
        let trimmed = lines[keepFrom...].joined(separator: "\n")
        try? trimmed.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        applyLockSafeProtection(to: fileURL)
    }

    private func flushBufferedLines() {
        lock.lock()
        defer { lock.unlock() }
        flushBufferedLinesLocked()
    }

    private func flushBufferedLinesLocked() {
        guard let fileURL = fileURL, !bufferedLines.isEmpty else { return }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int,
           size > NimaConstants.maxLogSizeBytes {
            rotateLog(at: fileURL)
        }

        let joined = bufferedLines.joined()
        bufferedLines.removeAll(keepingCapacity: true)
        bufferedBytes = 0

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            if let data = joined.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            try? joined.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        }

        let now = Date()
        if now.timeIntervalSince(lastProtectionApplyAt) >= NimaConstants.tunnelLogFlushIntervalSeconds {
            applyLockSafeProtection(to: fileURL)
            lastProtectionApplyAt = now
        }
    }

    private func applyLockSafeProtection(to fileURL: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }
}
