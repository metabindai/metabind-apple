import UserNotifications

/// Manages local push notifications for the demo.
///
/// This is standard `UNUserNotificationCenter` code — nothing Metabind-specific.
/// In a real app you'd receive a remote push whose payload includes a Metabind
/// content ID, then present it with ``NotificationContentSheet``. Here we
/// simulate that by scheduling a local notification with a short delay.
class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    var onNotificationTapped: (() -> Void)?

    private static let categoryId = "PROMOTION"
    private static let viewActionId = "VIEW_PROMOTION"

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    private func registerCategories() {
        let viewAction = UNNotificationAction(
            identifier: Self.viewActionId,
            title: "View Promotion",
            options: .foreground
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Not Now",
            options: .destructive
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [viewAction, dismissAction],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func schedulePromotionNotification() async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
        } catch {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "New Promotion"
        content.subtitle = "Don't miss out"
        content.body = "Tap to view the latest promotion from Oak&Ivory."
        content.sound = .default
        content.categoryIdentifier = Self.categoryId

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionId = response.actionIdentifier
        if actionId == Self.viewActionId || actionId == UNNotificationDefaultActionIdentifier {
            onNotificationTapped?()
        }
        completionHandler()
    }
}
