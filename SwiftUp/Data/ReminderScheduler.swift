import Foundation
import UserNotifications

/// The Settings notification switches, read back from the same `@AppStorage` keys `SettingsView`
/// writes. Defaults mirror the switches' own defaults (all on).
struct NotificationPreferences: Hashable {
    enum Keys {
        static let dailyReminder = "settings.notifications.dailyReminder"
        static let streakAtRisk = "settings.notifications.streakAtRisk"
        static let weeklyEdition = "settings.notifications.weeklyEdition"
        static let quietHours = "settings.notifications.quietHours"
    }

    var dailyReminder = true
    var streakAtRisk = true
    var weeklyEdition = true
    var quietHours = true

    var anyEnabled: Bool { dailyReminder || streakAtRisk || weeklyEdition }
}

struct PlannedNotification: Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
}

/// Pure "what should be pending right now" — no `UNUserNotificationCenter`, so it's unit-testable
/// against a fixed clock. Everything is one-shot and dated rather than a repeating trigger: a
/// repeating daily trigger can't skip today once the quiz is done, and the streak alert depends on
/// state only known at scheduling time. `ReminderScheduler` re-plans every time the app comes to
/// the foreground or that state changes, so the window only has to outlast a stretch of not
/// opening the app.
enum NotificationPlanner {
    static let dailyReminderTime = (hour: 7, minute: 30)
    static let streakAtRiskTime = (hour: 21, minute: 0)
    static let weeklyEditionTime = (weekday: 1, hour: 9, minute: 0) // Sunday
    static let quietHours = (startHour: 22, endHour: 7)

    static func plan(
        now: Date,
        calendar: Calendar = .current,
        preferences: NotificationPreferences,
        completedToday: Bool,
        streakDays: Int,
        daysAhead: Int = 14
    ) -> [PlannedNotification] {
        let today = calendar.startOfDay(for: now)
        var planned: [PlannedNotification] = []

        func at(dayOffset: Int, hour: Int, minute: Int) -> Date? {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }

        if preferences.dailyReminder {
            for offset in (completedToday ? 1 : 0)..<daysAhead {
                guard let date = at(dayOffset: offset, hour: dailyReminderTime.hour, minute: dailyReminderTime.minute)
                else { continue }
                planned.append(PlannedNotification(
                    id: "daily.\(offset)", title: "Today's five are in",
                    body: "Five questions, a few minutes. Keep your Swift sharp.", fireDate: date
                ))
            }
        }

        // Only the next evening the streak can actually be lost: tonight if today's quiz is still
        // open, otherwise tomorrow night. Anything further out would claim a streak that will
        // already have lapsed by then.
        if preferences.streakAtRisk, streakDays > 0,
           let date = at(dayOffset: completedToday ? 1 : 0, hour: streakAtRiskTime.hour, minute: streakAtRiskTime.minute) {
            let days = streakDays == 1 ? "1-day streak" : "\(streakDays)-day streak"
            planned.append(PlannedNotification(
                id: "streakAtRisk", title: "Your streak is at risk",
                body: "Your \(days) ends at midnight. Today's five are still waiting.", fireDate: date
            ))
        }

        if preferences.weeklyEdition {
            var cursor = now
            var index = 0
            let components = DateComponents(
                hour: weeklyEditionTime.hour, minute: weeklyEditionTime.minute, weekday: weeklyEditionTime.weekday
            )
            while let next = calendar.nextDate(after: cursor, matching: components, matchingPolicy: .nextTime),
                  let horizon = calendar.date(byAdding: .day, value: daysAhead, to: today), next < horizon {
                planned.append(PlannedNotification(
                    id: "weekly.\(index)", title: "The weekly edition",
                    body: "A new week of questions starts today. See how last week went on your Profile.",
                    fireDate: next
                ))
                cursor = next
                index += 1
            }
        }

        return planned
            .map { preferences.quietHours ? deferredPastQuietHours($0, calendar: calendar) : $0 }
            .filter { $0.fireDate > now }
            .sorted { $0.fireDate < $1.fireDate }
    }

    /// Holds a notification that would land inside 22:00–07:00 until 07:00.
    private static func deferredPastQuietHours(_ note: PlannedNotification, calendar: Calendar) -> PlannedNotification {
        let hour = calendar.component(.hour, from: note.fireDate)
        let day = calendar.startOfDay(for: note.fireDate)
        let release: Date?
        if hour >= quietHours.startHour {
            release = calendar.date(byAdding: .day, value: 1, to: day)
                .flatMap { calendar.date(bySettingHour: quietHours.endHour, minute: 0, second: 0, of: $0) }
        } else if hour < quietHours.endHour {
            release = calendar.date(bySettingHour: quietHours.endHour, minute: 0, second: 0, of: day)
        } else {
            return note
        }
        guard let release else { return note }
        return PlannedNotification(id: note.id, title: note.title, body: note.body, fireDate: release)
    }
}

/// Applies `NotificationPlanner`'s plan to the system. Every refresh replaces the whole pending
/// set — the app has no other local notifications, so there's nothing to preserve.
@MainActor
enum ReminderScheduler {
    private static var center: UNUserNotificationCenter { .current() }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Prompts only the first time; afterwards returns whatever the user chose.
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        switch await authorizationStatus() {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    static func refresh(preferences: NotificationPreferences, completedToday: Bool, streakDays: Int) async {
        center.removeAllPendingNotificationRequests()
        guard preferences.anyEnabled, await requestAuthorizationIfNeeded() else { return }

        let calendar = Calendar.current
        let plan = NotificationPlanner.plan(
            now: Date(), calendar: calendar, preferences: preferences,
            completedToday: completedToday, streakDays: streakDays
        )
        for note in plan {
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: note.fireDate),
                repeats: false
            )
            try? await center.add(UNNotificationRequest(identifier: note.id, content: content, trigger: trigger))
        }
    }

    /// On sign-out: the next account shouldn't inherit the last one's streak alerts.
    static func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
