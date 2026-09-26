import Foundation

enum DisplayFormat {
    static func syncDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMdjm")
        return formatter.string(from: date)
    }

    /// List-style hours: whole hours above one hour, one decimal below.
    static func compactHours(_ minutes: Int) -> String {
        guard minutes >= 3 else { return "0" }
        let hours = Double(minutes) / 60
        if hours >= 1 {
            return L10n.format("%lld 小时", Int(hours.rounded()))
        }
        return L10n.format("%.1f 小时", hours)
    }

    /// Stat-card hours with a decimal and locale grouping: 1,300.6 小时.
    static func totalHours(_ minutes: Int) -> String {
        let hours = Double(minutes) / 60
        return hours.formatted(.number.locale(L10n.locale).precision(.fractionLength(1))) + " " + L10n.tr("小时")
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
