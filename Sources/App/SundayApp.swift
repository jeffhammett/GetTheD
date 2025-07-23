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
        // Schedule the next refresh
        
        scheduleAppRefresh()

        // Create an async task to do the work
        Task {
            // 1. Get the current location
            locationManager.startUpdatingLocation()
            
            // It might take a moment to get the location, so we'll wait a bit.
            // A more robust solution might involve a continuation or a Combine publisher.
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            
            // 2. Fetch UV Data if we have a location
            if let location = locationManager.location {
                uvService.fetchUVData(for: location)
            }
            
            // A short delay to allow the async network request to complete
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

            // 3. Reload Widgets
            WidgetCenter.shared.reloadAllTimelines()
            
            // 4. Mark the task as complete
            task.setTaskCompleted(success: true)
        }
        
        // Expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
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
