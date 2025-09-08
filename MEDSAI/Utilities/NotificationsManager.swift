// NotificationsManager.swift
import Foundation
import UserNotifications
import UIKit

// MARK: - Broadcasts to refresh UI live when background actions change completion state
extension Notification.Name {
    static let doseCompletionChanged = Notification.Name("doseCompletionChanged")
    static let apptCompletionChanged = Notification.Name("apptCompletionChanged")
}

/// Persist completion ticks so notification actions can update state even when the app is backgrounded.
enum CompletionStore {
    private static let apptKey = "completedAppointments"
    private static let doseKey = "completedDoses"

    static func completedAppointments() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: apptKey) ?? []
        return Set(arr)
    }
    static func setCompletedAppointments(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: apptKey)
        NotificationCenter.default.post(name: .apptCompletionChanged, object: nil)
    }
    static func toggleAppointment(_ id: String) {
        var s = completedAppointments()
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        setCompletedAppointments(s)
    }
    static func markAppointmentDone(_ id: String) {
        var s = completedAppointments()
        s.insert(id)
        setCompletedAppointments(s)
    }

    static func completedDoses() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: doseKey) ?? []
        return Set(arr)
    }
    static func setCompletedDoses(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: doseKey)
        NotificationCenter.default.post(name: .doseCompletionChanged, object: nil)
    }
    static func toggleDose(_ id: String) {
        var s = completedDoses()
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        setCompletedDoses(s)
    }
    static func markDoseDone(_ id: String) {
        var s = completedDoses()
        s.insert(id)
        setCompletedDoses(s)
    }
}

/// Central notifications helper + delegate for action buttons.
final class NotificationsManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsManager()

    // Categories / action identifiers
    struct IDs {
        static let doseCategory = "DOSE_CATEGORY"
        static let apptCategory = "APPT_CATEGORY"

        static let actionDoseDone = "ACTION_DOSE_DONE"
    }

    // MARK: Setup (call once at app launch)
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories(center: center)
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let ok = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return ok
        } catch {
            return false
        }
    }

    private func registerCategories(center: UNUserNotificationCenter = .current()) {
        // Doses: include a "Took the dose" button to tick from the notification itself
        let done = UNNotificationAction(
            identifier: IDs.actionDoseDone,
            title: "Took the dose",
            options: [.authenticationRequired] // require unlock
        )
        let dose = UNNotificationCategory(
            identifier: IDs.doseCategory,
            actions: [done],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Appointments: read-only (no actions for now)
        let appt = UNNotificationCategory(
            identifier: IDs.apptCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([dose, appt])
    }

    // MARK: Scheduling / cancel

    /// Schedules a one-shot local notification at a specific date.
    func schedule(
        id: String,
        title: String,
        body: String,
        at date: Date,
        categoryId: String? = nil,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        // Avoid “random” feeling: only future alarms; normalize seconds to 0.
        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let cat = categoryId { content.categoryIdentifier = cat }
        if !userInfo.isEmpty { content.userInfo = userInfo }

        // Normalize seconds -> 0 to avoid minor drift
        var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        comps.second = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Handle action (button) taps or default taps on the notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier

        // We only mark done when the explicit action button is used.
        if action == IDs.actionDoseDone, let doseKey = info["doseKey"] as? String {
            // Mark as done + cancel its follow-up ping
            CompletionStore.markDoseDone(doseKey)
            let followupId = "DOSE_FU_" + doseKey
            self.cancel(ids: [followupId])
        }

        completionHandler()
    }

    // Make banners visible when the app is foregrounded.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .list]
    }
}
