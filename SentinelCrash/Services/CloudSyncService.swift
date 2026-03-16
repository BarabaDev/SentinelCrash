import Foundation
import Combine

/// Syncs read/hidden crash paths across devices using iCloud Key-Value Store.
final class CloudSyncService: ObservableObject {

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(syncEnabled, forKey: "cloudSyncEnabled")
            if syncEnabled { startSync() } else { stopSync() }
        }
    }
    @Published var syncStatus: String = "Idle"

    private let store = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?

    private let readPathsKey = "cloud_readCrashPaths"
    private let hiddenPathsKey = "cloud_hiddenCrashPaths"
    private let favPathsKey = "cloud_favoriteCrashPaths"
    private let lastSyncKey = "cloud_lastSyncDate"

    init() {
        self.syncEnabled = UserDefaults.standard.bool(forKey: "cloudSyncEnabled")
        if syncEnabled { startSync() }
    }

    deinit {
        stopSync()
    }

    // MARK: - Push

    func pushToCloud(readPaths: Set<String>, hiddenPaths: Set<String>, favoritePaths: Set<String> = []) {
        guard syncEnabled else { return }
        guard FileManager.default.ubiquityIdentityToken != nil else {
            DispatchQueue.main.async { [weak self] in self?.syncStatus = "iCloud Unavailable" }
            return
        }

        let cloudRead = Set(store.array(forKey: readPathsKey) as? [String] ?? [])
        let cloudHidden = Set(store.array(forKey: hiddenPathsKey) as? [String] ?? [])
        let cloudFavs = Set(store.array(forKey: favPathsKey) as? [String] ?? [])

        store.set(Array(cloudRead.union(readPaths)), forKey: readPathsKey)
        store.set(Array(cloudHidden.union(hiddenPaths)), forKey: hiddenPathsKey)
        store.set(Array(cloudFavs.union(favoritePaths)), forKey: favPathsKey)
        store.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
        store.synchronize()

        DispatchQueue.main.async { [weak self] in
            self?.lastSyncDate = Date()
            self?.syncStatus = "Synced"
        }
    }

    // MARK: - Pull

    func pullFromCloud() -> (readPaths: Set<String>, hiddenPaths: Set<String>, favoritePaths: Set<String>) {
        guard syncEnabled else { return ([], [], []) }
        guard FileManager.default.ubiquityIdentityToken != nil else {
            DispatchQueue.main.async { [weak self] in self?.syncStatus = "iCloud Unavailable" }
            return ([], [], [])
        }
        store.synchronize()

        let read = Set(store.array(forKey: readPathsKey) as? [String] ?? [])
        let hidden = Set(store.array(forKey: hiddenPathsKey) as? [String] ?? [])
        let favs = Set(store.array(forKey: favPathsKey) as? [String] ?? [])

        let timestamp = store.double(forKey: lastSyncKey)
        if timestamp > 0 {
            DispatchQueue.main.async { [weak self] in
                self?.lastSyncDate = Date(timeIntervalSince1970: timestamp)
                self?.syncStatus = "Synced"
            }
        }

        return (read, hidden, favs)
    }

    // MARK: - Clear

    func clearCloudData() {
        store.removeObject(forKey: readPathsKey)
        store.removeObject(forKey: hiddenPathsKey)
        store.removeObject(forKey: favPathsKey)
        store.removeObject(forKey: lastSyncKey)
        store.synchronize()
        syncStatus = "Idle"
        lastSyncDate = nil
    }

    // MARK: - Lifecycle

    private func startSync() {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            syncStatus = "iCloud Unavailable"
            return
        }

        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.syncStatus = "Synced"
            self?.lastSyncDate = Date()
            NotificationCenter.default.post(name: Notification.Name("cloudSyncDidReceiveUpdate"), object: nil)
        }

        store.synchronize()
        syncStatus = "Synced"
    }

    private func stopSync() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        syncStatus = "Idle"
    }
}
