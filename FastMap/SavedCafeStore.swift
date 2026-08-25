//
//  SavedCafeStore.swift
//  CoFFMap
//
//  즐겨찾기한 카페를 기기와 iCloud에 저장합니다.
//
//  ⚠️ 여기가 Kakao 약관과 만나는 지점입니다.
//  카카오는 Local API 응답을 원본이든 가공본이든 저장하지 못하게 합니다. 그래서 화면에 뜬
//  Kakao 카페를 그대로 저장할 수 없습니다. 대신 즐겨찾기를 누른 그 순간에
//  `AppleCafeResolver`가 Apple 지도에서 같은 카페를 다시 찾고, 저장은 그 Apple 값으로 합니다.
//
//  즉 `save`로 들어오는 모든 값은 `source == .apple`이어야 합니다. `store(_:)`가 이를 지킵니다.
//  Apple 지도에서 짝을 못 찾으면 저장하지 않고 사용자에게 알려 줍니다 — 몰래 Kakao 값을
//  저장하는 것보다 낫습니다.
//
//  CloudKit 레코드 타입은 "SavedPlace" 그대로 둡니다. 이미 저장해 둔 즐겨찾기를 잃지 않기 위해서입니다.
//

import CloudKit
import Combine
import CoreLocation
import CryptoKit
import Foundation

@MainActor
final class SavedCafeStore: ObservableObject {
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

    @Published private(set) var cafes: [Cafe] = []
    @Published private(set) var syncState: SyncState = .idle
    /// 저장에 실패했을 때 화면에 띄울 한 줄. 표시한 뒤 nil로 되돌립니다.
    @Published var saveFailureMessage: String?

    private var cloudContainer: CKContainer?
    private var database: CKDatabase?
    private var accountIdentifier: String?

    private let resolver = AppleCafeResolver()
    private static let recordType = "SavedPlace"

    /// 화면에 떠 있던 카페의 id → 실제로 저장된 카페의 id.
    ///
    /// 저장은 Apple 값으로 하는데, Apple이 돌려주는 id·이름·좌표가 Kakao와 다릅니다.
    /// (좌표는 120m까지 어긋나도 같은 곳으로 받아들입니다.) 그래서 이 표가 없으면
    /// 방금 저장한 카페인데도 북마크가 빈 채로 보이고, 한 번 더 누르면 중복 저장됩니다.
    /// 기기에만 두는 값이라 다른 기기에서는 아래 근접 매칭이 대신 잡아 줍니다.
    private var savedIDBySourceID: [String: String] = [:]

    // MARK: - 준비

    func configure(for account: AppleAccount?) async {
        accountIdentifier = account?.userIdentifier
        guard let accountIdentifier else {
            cafes = []
            savedIDBySourceID = [:]
            syncState = .idle
            return
        }

        cafes = loadCache(for: accountIdentifier)
#if targetEnvironment(simulator)
        syncState = .localOnly("시뮬레이터 로컬 저장")
#else
        let container = CKContainer.default()
        cloudContainer = container
        database = container.privateCloudDatabase
        await synchronizeFromCloud()
#endif
    }

    // MARK: - 조회

    /// 이미 저장돼 있는지. Kakao와 Apple은 id 체계가 달라서 좌표·이름으로도 봅니다.
    func contains(_ cafe: Cafe) -> Bool {
        savedMatch(for: cafe) != nil
    }

    private func savedMatch(for cafe: Cafe) -> Cafe? {
        if let byID = cafes.first(where: { $0.id == cafe.id }) { return byID }

        if let mappedID = savedIDBySourceID[cafe.id],
           let byMapping = cafes.first(where: { $0.id == mappedID }) {
            return byMapping
        }

        if let byPin = cafes.first(where: { $0.dedupeKey == cafe.dedupeKey }) { return byPin }

        // 표에도 없고 좌표 격자도 안 맞는 경우 — 다른 기기에서 저장했거나,
        // Apple이 좌표를 꽤 옮겨 놓은 경우입니다. 이름과 거리로 한 번 더 봅니다.
        return cafes.first { isLikelySamePlace($0, cafe) }
    }

    /// 두 카페가 같은 곳으로 볼 만한지. 저장 시 허용한 오차(120m)와 눈높이를 맞춥니다.
    private func isLikelySamePlace(_ lhs: Cafe, _ rhs: Cafe) -> Bool {
        guard GeoMath.distanceMeters(from: lhs.coordinate, to: rhs.coordinate) <= 150 else { return false }
        let a = normalizedName(lhs.name)
        let b = normalizedName(rhs.name)
        guard !a.isEmpty, !b.isEmpty else { return false }
        // "스타벅스시청점"과 "스타벅스서울시청점"처럼 한쪽이 다른 쪽을 품는 경우가 많습니다.
        return a == b || a.contains(b) || b.contains(a)
    }

    private func normalizedName(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && $0 != "." && $0 != "-" }
    }

    // MARK: - 저장과 삭제

    func toggle(_ cafe: Cafe) async {
        guard accountIdentifier != nil else { return }

        if let existing = savedMatch(for: cafe) {
            await remove(existing)
        } else {
            await add(cafe)
        }
    }

    /// 저장 가능한 형태로 바꾼 뒤에만 저장합니다.
    private func add(_ cafe: Cafe) async {
        guard let accountIdentifier else { return }

        guard let storable = await storableVersion(of: cafe) else {
            saveFailureMessage = "‘\(cafe.name)’은(는) Apple 지도에서 찾지 못해 저장할 수 없어요."
            return
        }

        cafes.append(storable)
        cafes.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        savedIDBySourceID[cafe.id] = storable.id
        saveCache(for: accountIdentifier)
        await saveToCloud(storable)
    }

    func remove(_ cafe: Cafe) async {
        guard let accountIdentifier else { return }
        let target = savedMatch(for: cafe) ?? cafe
        cafes.removeAll { $0.id == target.id }
        savedIDBySourceID = savedIDBySourceID.filter { $0.value != target.id }
        saveCache(for: accountIdentifier)
        await deleteFromCloud(target)
    }

    /// Kakao 카페는 Apple 값으로 바꿔서 돌려주고, 이미 Apple이면 그대로 둡니다.
    /// 미리보기 값은 저장 대상이 아닙니다.
    private func storableVersion(of cafe: Cafe) async -> Cafe? {
        switch cafe.source {
        case .apple:
            return cafe
        case .preview:
            return nil
        case .kakao:
            return await resolver.resolve(cafe)
        }
    }

    // MARK: - CloudKit

    private func synchronizeFromCloud() async {
        guard let accountIdentifier, let cloudContainer, let database else { return }
        syncState = .syncing

        do {
            let accountStatus = try await cloudContainer.accountStatus()
            guard accountStatus == .available else {
                syncState = .localOnly("iCloud 계정 사용 불가")
                return
            }

            let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
            let result = try await database.records(matching: query, resultsLimit: 200)
            let cloudCafes = result.matchResults.compactMap { _, recordResult -> Cafe? in
                guard case .success(let record) = recordResult else { return nil }
                return cafe(from: record)
            }

            if !cloudCafes.isEmpty || cafes.isEmpty {
                cafes = cloudCafes.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                saveCache(for: accountIdentifier)
            } else {
                // 클라우드가 비어 있고 기기에만 있으면 올려 둡니다.
                for cafe in cafes {
                    await saveToCloud(cafe, updateState: false)
                }
            }
            syncState = .synced
        } catch {
            syncState = .localOnly(error.localizedDescription)
        }
    }

    private func saveToCloud(_ cafe: Cafe, updateState: Bool = true) async {
        guard let database else {
            if updateState { syncState = .localOnly("이 기기에 저장됨") }
            return
        }
        if updateState { syncState = .syncing }

        let record = CKRecord(recordType: Self.recordType, recordID: recordID(for: cafe))
        record["placeID"] = cafe.id as CKRecordValue
        record["name"] = cafe.name as CKRecordValue
        record["address"] = cafe.address as CKRecordValue
        record["roadAddress"] = (cafe.roadAddress ?? "") as CKRecordValue
        record["latitude"] = cafe.coordinate.latitude as CKRecordValue
        record["longitude"] = cafe.coordinate.longitude as CKRecordValue
        record["tags"] = cafe.orderedTags.map(\.rawValue).joined(separator: ",") as CKRecordValue
        record["savedAt"] = Date() as CKRecordValue

        do {
            _ = try await database.save(record)
            if updateState { syncState = .synced }
        } catch {
            if updateState { syncState = .localOnly(error.localizedDescription) }
        }
    }

    private func deleteFromCloud(_ cafe: Cafe) async {
        guard let database else {
            syncState = .localOnly("이 기기에 저장됨")
            return
        }
        syncState = .syncing
        do {
            _ = try await database.deleteRecord(withID: recordID(for: cafe))
            syncState = .synced
        } catch let error as CKError where error.code == .unknownItem {
            syncState = .synced
        } catch {
            syncState = .localOnly(error.localizedDescription)
        }
    }

    private func cafe(from record: CKRecord) -> Cafe? {
        guard let placeID = record["placeID"] as? String,
              let name = record["name"] as? String,
              let latitude = record["latitude"] as? Double,
              let longitude = record["longitude"] as? Double else { return nil }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let storedTags = (record["tags"] as? String)?
            .split(separator: ",")
            .compactMap { CafeTag(rawValue: String($0)) }

        return Cafe(
            id: placeID,
            name: name,
            address: record["address"] as? String ?? "",
            roadAddress: (record["roadAddress"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            coordinate: coordinate,
            distanceMeters: 0,
            bearingDegrees: 0,
            // 예전 레코드에는 태그가 없습니다. 그 자리에서 다시 계산해 채웁니다.
            tags: Set(storedTags ?? []).isEmpty
                ? CafeTagClassifier.tags(name: name, categoryName: nil, coordinate: coordinate)
                : Set(storedTags ?? []),
            source: .apple
        )
    }

    private func recordID(for cafe: Cafe) -> CKRecord.ID {
        let digest = SHA256.hash(data: Data(cafe.id.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return CKRecord.ID(recordName: "favorite-\(hash)")
    }

    // MARK: - 로컬 캐시

    private func cacheKey(for accountIdentifier: String) -> String {
        let digest = SHA256.hash(data: Data(accountIdentifier.utf8))
        return "saved-cafes-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func indexKey(for accountIdentifier: String) -> String {
        cacheKey(for: accountIdentifier) + "-source-index"
    }

    private func loadCache(for accountIdentifier: String) -> [Cafe] {
        savedIDBySourceID = UserDefaults.standard
            .dictionary(forKey: indexKey(for: accountIdentifier)) as? [String: String] ?? [:]

        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: accountIdentifier)) else { return [] }
        return (try? JSONDecoder().decode([Cafe].self, from: data)) ?? []
    }

    private func saveCache(for accountIdentifier: String) {
        UserDefaults.standard.set(savedIDBySourceID, forKey: indexKey(for: accountIdentifier))
        guard let data = try? JSONEncoder().encode(cafes) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(for: accountIdentifier))
    }
}
