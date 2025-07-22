import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications
import WidgetKit

@main
struct SundayApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var healthManager = HealthManager()
    @StateObject private var uvService = UVService()
    @StateObject private var vitaminDCalculator = VitaminDCalculator()
    @StateObject private var networkMonitor = NetworkMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                UserPreferences.self,
                VitaminDSession.self,
                CachedUVData.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, allowsSave: true)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            MigrationService.migrateUserDefaults(to: modelContainer.mainContext)
            registerBackgroundTask()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(healthManager)
                .environmentObject(uvService)
                .environmentObject(vitaminDCalculator)
                .environmentObject(networkMonitor)
                .modelContainer(modelContainer)
        }
        .onChange(of: scenePhase) { oldScenePhase, newScenePhase in
            if newScenePhase == .background {
                scheduleAppRefresh()
            }
        }
    }

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "jh.sunday.app.update", using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "jh.sunday.app.update")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // Fetch no more than every 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }

    func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let operation = BlockOperation {
            // 1. Fetch Location
            locationManager.startUpdatingLocation()

            // 2. Fetch UV Data
            if let location = locationManager.location {
                uvService.fetchUVData(for: location)
            }

            // 3. Reload Widgets
            WidgetCenter.shared.reloadAllTimelines()
        }

        task.expirationHandler = {
            queue.cancelAllOperations()
        }

        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        queue.addOperation(operation)
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var vitaminDCalculator: VitaminDCalculator?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        vitaminDCalculator?.updateLiveActivity()
        completionHandler([.banner, .sound])
    }
}
