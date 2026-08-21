import CloudKit
import Combine
import CryptoKit
import Foundation

@MainActor
final class SavedPlacesStore: ObservableObject {
    enum SyncState: Equatable {
        case idle
        case syncing
        case synced
        case localOnly(String)

        var text: String {
            switch self {
            case .idle: "동기화 대기 중"
            case .syncing: "iCloud 동기화 중"
            case .synced: "iCloud와 동기화됨"
            case .localOnly: "이 기기에 저장됨"
            }
        }
    }

    @Published private(set) var places: [Place] = []
    @Published private(set) var syncState: SyncState = .idle

    private var cloudContainer: CKContainer?
    private var database: CKDatabase?
    private var accountIdentifier: String?

    func configure(for account: AppleAccount?) async {
        accountIdentifier = account?.userIdentifier
        guard let accountIdentifier else {
            places = []
            syncState = .idle
            return
        }

        places = loadCache(for: accountIdentifier)
#if targetEnvironment(simulator)
        syncState = .localOnly("시뮬레이터 로컬 저장")
#else
        let container = CKContainer.default()
        cloudContainer = container
        database = container.privateCloudDatabase
        await synchronizeFromCloud()
#endif
    }

    func contains(_ place: Place) -> Bool {
        places.contains { $0.id == place.id }
    }

    func toggle(_ place: Place) async {
        guard let accountIdentifier else { return }
        if contains(place) {
            places.removeAll { $0.id == place.id }
            saveCache(for: accountIdentifier)
            await deleteFromCloud(place)
        } else {
            places.append(place)
            places.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            saveCache(for: accountIdentifier)
            await saveToCloud(place)
        }
    }

    func remove(_ place: Place) async {
        guard let accountIdentifier else { return }
        places.removeAll { $0.id == place.id }
        saveCache(for: accountIdentifier)
        await deleteFromCloud(place)
    }

    private func synchronizeFromCloud() async {
        guard let accountIdentifier, let cloudContainer, let database else { return }
        syncState = .syncing

        do {
            let accountStatus = try await cloudContainer.accountStatus()
            guard accountStatus == .available else {
                syncState = .localOnly("iCloud 계정 사용 불가")
                return
            }

            let query = CKQuery(recordType: "SavedPlace", predicate: NSPredicate(value: true))
            let result = try await database.records(matching: query, resultsLimit: 200)
            let cloudPlaces = result.matchResults.compactMap { _, recordResult -> Place? in
                guard case .success(let record) = recordResult else { return nil }
                return place(from: record)
            }

            if !cloudPlaces.isEmpty || places.isEmpty {
                places = cloudPlaces.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                saveCache(for: accountIdentifier)
            } else {
                for place in places {
                    await saveToCloud(place, updateState: false)
                }
            }
            syncState = .synced
        } catch {
            syncState = .localOnly(error.localizedDescription)
        }
    }

    private func saveToCloud(_ place: Place, updateState: Bool = true) async {
        guard let database else {
            if updateState { syncState = .localOnly("이 기기에 저장됨") }
            return
        }
        if updateState { syncState = .syncing }
        let record = CKRecord(recordType: "SavedPlace", recordID: recordID(for: place))
        record["placeID"] = place.id as CKRecordValue
        record["name"] = place.name as CKRecordValue
        record["category"] = place.category.id as CKRecordValue
        // 사용자가 만든 카테고리는 id만으로 복원할 수 없으므로 전체를 함께 저장합니다.
        if let categoryData = try? JSONEncoder().encode(place.category),
           let categoryJSON = String(data: categoryData, encoding: .utf8) {
            record["categoryData"] = categoryJSON as CKRecordValue
        }
        record["address"] = place.address as CKRecordValue
        record["latitude"] = place.coordinate.latitude as CKRecordValue
        record["longitude"] = place.coordinate.longitude as CKRecordValue
        record["distanceMeters"] = place.distanceMeters as CKRecordValue
        record["bearingDegrees"] = place.bearingDegrees as CKRecordValue
        record["savedAt"] = Date() as CKRecordValue

        do {
            _ = try await database.save(record)
            if updateState { syncState = .synced }
        } catch {
            if updateState { syncState = .localOnly(error.localizedDescription) }
        }
    }

    private func deleteFromCloud(_ place: Place) async {
        guard let database else {
            syncState = .localOnly("이 기기에 저장됨")
            return
        }
        syncState = .syncing
        do {
            _ = try await database.deleteRecord(withID: recordID(for: place))
            syncState = .synced
        } catch let error as CKError where error.code == .unknownItem {
            syncState = .synced
        } catch {
            syncState = .localOnly(error.localizedDescription)
        }
    }

    private func place(from record: CKRecord) -> Place? {
        guard let placeID = record["placeID"] as? String,
              let name = record["name"] as? String,
              let categoryID = record["category"] as? String,
              let address = record["address"] as? String,
              let latitude = record["latitude"] as? Double,
              let longitude = record["longitude"] as? Double else { return nil }

        let category = decodedCategory(from: record) ?? PlaceCategory.builtIn(id: categoryID)
            ?? PlaceCategory(id: categoryID, title: categoryID)

        return Place(
            id: placeID,
            name: name,
            category: category,
            address: address,
            coordinate: .init(latitude: latitude, longitude: longitude),
            distanceMeters: record["distanceMeters"] as? Double ?? 0,
            bearingDegrees: record["bearingDegrees"] as? Double ?? 0
        )
    }

    private func decodedCategory(from record: CKRecord) -> PlaceCategory? {
        guard let json = record["categoryData"] as? String,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlaceCategory.self, from: data)
    }

    private func recordID(for place: Place) -> CKRecord.ID {
        let digest = SHA256.hash(data: Data(place.id.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return CKRecord.ID(recordName: "favorite-\(hash)")
    }

    private func cacheKey(for accountIdentifier: String) -> String {
        let digest = SHA256.hash(data: Data(accountIdentifier.utf8))
        return "saved-places-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func loadCache(for accountIdentifier: String) -> [Place] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: accountIdentifier)) else { return [] }
        return (try? JSONDecoder().decode([Place].self, from: data)) ?? []
    }

    private func saveCache(for accountIdentifier: String) {
        guard let data = try? JSONEncoder().encode(places) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(for: accountIdentifier))
    }

}
