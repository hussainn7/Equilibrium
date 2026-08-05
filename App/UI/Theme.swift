import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0B0F14)
    static let card = Color(hex: 0x141A22)
    static let cardElevated = Color(hex: 0x1C242E)
    static let stroke = Color(hex: 0x232D38)
    static let textPrimary = Color(hex: 0xF0F4F8)
    static let textSecondary = Color(hex: 0x8A97A5)

    static let green = Color(hex: 0x2FD673)
    static let yellow = Color(hex: 0xF5C542)
    static let red = Color(hex: 0xEF5350)
    static let strainBlue = Color(hex: 0x4A9DFF)
    static let sleepPurple = Color(hex: 0x9B8CFF)
    static let teal = Color(hex: 0x35D0BA)
    static let orange = Color(hex: 0xFF9F4A)

    static func recoveryColor(zone: RecoveryZone) -> Color {
        switch zone {
        case .green: return green
        case .yellow: return yellow
        case .red: return red
        }
    }

    static func recoveryColor(score: Int) -> Color {
        if score >= 67 { return green }
        if score >= 34 { return yellow }
        return red
    }

    static func stageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return orange
        case .rem: return teal
        case .light: return sleepPurple.opacity(0.75)
        case .deep: return Color(hex: 0x5B4BD6)
        case .unknown: return textSecondary
        }
    }

    static func stageName(_ stage: SleepStage) -> String {
        switch stage {
        case .awake: return "Awake"
        case .rem: return "REM"
        case .light: return "Light"
        case .deep: return "Deep"
        case .unknown: return "Unknown"
        }
    }

    static func bandColor(_ state: BandState) -> Color {
        switch state {
        case .inRange: return green
        case .above, .below: return orange
        case .noData, .calibrating: return textSecondary
        }
    }

    static func bandLabel(_ state: BandState) -> String {
        switch state {
        case .inRange: return "in range"
        case .above: return "elevated"
        case .below: return "low"
        case .noData: return "no data"
        case .calibrating: return "calibrating"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Formatting helpers.
enum Fmt {
    private static let english = Locale(identifier: "en_US")

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = english
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = english
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let dayShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = english
        f.dateFormat = "EE M/d"
        return f
    }()

    private static let weekdayLetterFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = english
        f.dateFormat = "EEEEE"
        return f
    }()

    /// Minuten → "7:36"
    static func hm(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    static func dayTitle(_ key: String) -> String {
        guard let date = DayKey.date(from: key) else { return key }
        if key == DayKey.today() { return "Today" }
        if key == DayKey.addDays(DayKey.today(), -1) { return "Yesterday" }
        return dayTitleFormatter.string(from: date)
    }

    static func dayShort(_ key: String) -> String {
        guard let date = DayKey.date(from: key) else { return key }
        return dayShortFormatter.string(from: date)
    }

    static func weekdayLetter(_ key: String) -> String {
        guard let date = DayKey.date(from: key) else { return "?" }
        return weekdayLetterFormatter.string(from: date)
    }

    static func dayNumber(_ key: String) -> String {
        String(key.suffix(2)).hasPrefix("0") ? String(key.suffix(1)) : String(key.suffix(2))
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = english
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
