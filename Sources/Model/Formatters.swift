import Foundation

enum Fmt {
    static func compactTokens(_ value: Int?) -> String {
        guard let value else { return "—" }
        let double = Double(value)
        switch double {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return String(format: "%.1fk", double / 1_000)
        case ..<1_000_000_000: return String(format: "%.2fM", double / 1_000_000)
        default: return String(format: "%.2fB", double / 1_000_000_000)
        }
    }

    static func grouped(_ value: Int?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func bytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB, .useMB, .useTB]
        return formatter.string(fromByteCount: value)
    }

    static func compactBytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        let gigabytes = Double(value) / 1_073_741_824
        if gigabytes >= 1 { return String(format: "%.0f GB", gigabytes) }
        return String(format: "%.0f MB", Double(value) / 1_048_576)
    }

    static func duration(_ interval: TimeInterval?) -> String {
        guard let interval, interval >= 0 else { return "—" }
        let total = Int(interval.rounded())
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if days > 0 { return "\(days)天\(hours)小时" }
        if hours > 0 { return "\(hours)小时\(minutes)分" }
        if minutes > 0 { return "\(minutes)分\(seconds)秒" }
        return "\(seconds)秒"
    }

    static func shortDuration(_ interval: TimeInterval?) -> String {
        guard let interval, interval >= 0 else { return "—" }
        if interval < 60 { return String(format: "%.0f秒", interval) }
        return duration(interval)
    }

    static func tps(_ value: Double?) -> String {
        guard let value, value > 0 else { return "0" }
        if value >= 100 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        let normalized = value <= 1.0 ? value * 100 : value
        return String(format: "%.1f%%", normalized)
    }

    static func clock(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func sinceNow(_ date: Date?) -> String {
        guard let date else { return "从未" }
        return duration(-date.timeIntervalSinceNow) + "前"
    }
}
