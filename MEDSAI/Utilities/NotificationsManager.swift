// NotificationsManager.swift
import Foundation
import UserNotifications
import UIKit

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
        // (you can add ACTION_APPT_DONE later if you want)
    }

    // MARK: Setup

    /// Optional: Call once at app start if you want.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories(center: center)
    }

    /// Ask for permission. Also ensures categories are registered and delegate is set,
    /// so things work even if `configure()` wasn't called elsewhere.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let ok = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            center.delegate = self
            registerCategories(center: center)
            return ok
        } catch {
            // Still ensure categories/delegate so action handling works if user had already granted perms earlier.
            center.delegate = self
            registerCategories(center: center)
            return false
        }
    }

    private func registerCategories(center: UNUserNotificationCenter = .current()) {
        // Doses: include a "Took the dose" button to tick from the notification itself
        let done = UNNotificationAction(
            identifier: IDs.actionDoseDone,
            title: "Took the dose ✅",
            options: [.authenticationRequired] // require unlock for safety
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
        guard date > Date() else { return } // don't schedule in the past

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let cat = categoryId { content.categoryIdentifier = cat }
        if !userInfo.isEmpty { content.userInfo = userInfo }

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Handle "Took the dose ✅" action for dose notifications (works in background).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier

        if action == IDs.actionDoseDone {
            if let doseKey = info["doseKey"] as? String {
                // Mark done and cancel follow-up notifications for this dose
                CompletionStore.markDoseDone(doseKey)
                let followupId = "DOSE_FU_" + doseKey
                self.cancel(ids: [followupId])
            }
        }

        // If the user dismissed the dose notification without tapping the action,
        // we do nothing — the follow-up (if scheduled) will still fire.

        completionHandler()
    }

    /// Show notifications while app is in foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .list]
    }
}
