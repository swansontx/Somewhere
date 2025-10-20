import Foundation
import CoreLocation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class DropStore: ObservableObject {
    private let db = Firestore.firestore()

    // Published state for UI
    @Published var currentUser: User? = nil
    @Published var drops: [DropItem] = []
    @Published private(set) var updatingDropIds: Set<String> = []

    private var listener: ListenerRegistration?

    init() {
        Task { await ensureSignedIn() }
    }

    // MARK: - Authentication Handling

    /// Ensures there's a Firebase Auth user (Apple or anonymous)
    func ensureSignedIn() async {
        if Auth.auth().currentUser == nil {
            do {
                let result = try await Auth.auth().signInAnonymously()
                print("Signed in anonymously as \(result.user.uid)")
            } catch {
                print("Anonymous sign-in failed:", error.localizedDescription)
            }
        }

        if let authUser = Auth.auth().currentUser {
            self.currentUser = User(id: authUser.uid,
                                    name: authUser.displayName ?? "Guest")
        }
    }

    /// Signs the user out completely (forces re-auth next launch)
    func signOut() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
            drops.removeAll()
        } catch {
            print("Error signing out:", error.localizedDescription)
        }
    }

    // MARK: - Drop Creation

    func createDrop(text: String,
                    visibility: DropVisibility,
                    at coordinate: CLLocationCoordinate2D) {
        guard let user = Auth.auth().currentUser else {
            print("User not signed in")
            return
        }

        let geohash = Geohash.encode(latitude: coordinate.latitude,
                                     longitude: coordinate.longitude,
                                     precision: 7)

        let data: [String: Any] = [
            "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
            "authorId": user.uid,
            "createdAt": Timestamp(date: Date()),
            "visibility": visibility.rawValue,
            "location": GeoPoint(latitude: coordinate.latitude,
                                 longitude: coordinate.longitude),
            "geohash": geohash,
            "reactionsCount": 0,
            "liftsCount": 0
        ]

        db.collection("drops").addDocument(data: data) { error in
            if let error = error {
                print("Error creating drop:", error.localizedDescription)
            } else {
                print("✅ Drop created successfully")
            }
        }
    }

    // MARK: - Nearby Fetch / Realtime Listener

    func listenNearby(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        listener?.remove()

        let prefixes = Geohash.prefixesCovering(
            region: (minLat, maxLat, minLon, maxLon),
            precision: 5
        )

        var collected: [String: DropItem] = [:]
        for prefix in prefixes {
            let start = prefix
            let end = prefix + "\u{f8ff}"

            db.collection("drops")
                .order(by: "geohash")
                .start(at: [start])
                .end(at: [end])
                .addSnapshotListener { [weak self] snap, err in
                    guard let self else { return }

                    if let err = err {
                        print("Firestore listener error:", err.localizedDescription)
                        return
                    }

                    if let docs = snap?.documents {
                        for doc in docs {
                            guard let item = self.makeDropItem(from: doc) else { continue }
                            collected[item.id] = item
                        }
                    }

                    let sortedDrops = collected.values.sorted(by: { $0.createdAt > $1.createdAt })
                    self.drops = sortedDrops

                    Task { [weak self] in
                        await self?.populateUserStats(for: sortedDrops.map { $0.id })
                    }
                }
        }
    }

    // MARK: - Reaction & Lift Persistence

    func isUpdating(dropId: String) -> Bool {
        updatingDropIds.contains(dropId)
    }

    func toggleLift(_ drop: DropItem) async {
        await persistStatChange(
            for: drop,
            statKey: "lifted",
            counterField: "liftsCount"
        )
    }

    func react(to drop: DropItem) async {
        await persistStatChange(
            for: drop,
            statKey: "reacted",
            counterField: "reactionsCount"
        )
    }

    private func persistStatChange(for drop: DropItem,
                                   statKey: String,
                                   counterField: String) async {
        guard let user = currentUser else {
            print("No authenticated user available to update stats")
            return
        }

        let dropId = drop.id
        if updatingDropIds.contains(dropId) { return }

        updatingDropIds.insert(dropId)
        defer { updatingDropIds.remove(dropId) }

        let dropRef = db.collection("drops").document(dropId)
        let statsRef = dropRef.collection("stats").document(user.id)

        do {
            let statsSnapshot = try await fetchDocument(statsRef)
            let statsData = statsSnapshot.data() ?? [:]
            let previousValue = statsData[statKey] as? Bool ?? false
            let newValue = !previousValue

            let batch = db.batch()
            batch.setData([statKey: newValue], forDocument: statsRef, merge: true)
            let delta = FieldValue.increment(Int64(newValue ? 1 : -1))
            batch.updateData([counterField: delta], forDocument: dropRef)

            try await commit(batch: batch)
            await refreshDrop(withId: dropId)
        } catch {
            print("Error updating stats for drop \(dropId):", error.localizedDescription)
        }
    }

    private func populateUserStats(for dropIds: [String]) async {
        guard let user = currentUser else { return }

        for dropId in dropIds {
            let statsRef = db.collection("drops").document(dropId).collection("stats").document(user.id)
            do {
                let snapshot = try await fetchDocument(statsRef)
                let data = snapshot.data() ?? [:]
                if let index = drops.firstIndex(where: { $0.id == dropId }) {
                    drops[index].hasReacted = data["reacted"] as? Bool ?? false
                    drops[index].isLiftedByCurrentUser = data["lifted"] as? Bool ?? false
                }
            } catch {
                print("Error loading stats for drop \(dropId):", error.localizedDescription)
            }
        }
    }

    private func refreshDrop(withId id: String) async {
        guard let user = currentUser else { return }

        let dropRef = db.collection("drops").document(id)

        do {
            let dropSnapshot = try await fetchDocument(dropRef)

            guard dropSnapshot.exists, let updatedDrop = makeDropItem(from: dropSnapshot) else {
                drops.removeAll { $0.id == id }
                return
            }

            let statsSnapshot = try await fetchDocument(dropRef.collection("stats").document(user.id))
            let statsData = statsSnapshot.data() ?? [:]
            var mergedDrop = updatedDrop
            mergedDrop.hasReacted = statsData["reacted"] as? Bool ?? false
            mergedDrop.isLiftedByCurrentUser = statsData["lifted"] as? Bool ?? false

            if let index = drops.firstIndex(where: { $0.id == id }) {
                drops[index] = mergedDrop
            } else {
                drops.append(mergedDrop)
                drops.sort(by: { $0.createdAt > $1.createdAt })
            }
        } catch {
            print("Error refreshing drop \(id):", error.localizedDescription)
        }
    }

    private func makeDropItem(from snapshot: DocumentSnapshot) -> DropItem? {
        let data = snapshot.data()

        guard
            let text = data?["text"] as? String,
            let visibilityRaw = data?["visibility"] as? String,
            let geoPoint = data?["location"] as? GeoPoint
        else { return nil }

        let authorId = data?["authorId"] as? String ?? "unknown"
        let author = User(id: authorId, name: "Unknown")
        let createdAt = (data?["createdAt"] as? Timestamp)?.dateValue() ?? .now
        let visibility = DropVisibility(rawValue: visibilityRaw) ?? .public
        let reactionCount = data?["reactionsCount"] as? Int
            ?? data?["reactions"] as? Int
            ?? 0
        let liftCount = data?["liftsCount"] as? Int ?? 0

        return DropItem(
            id: snapshot.documentID,
            text: text,
            author: author,
            createdAt: createdAt,
            coordinate: CLLocationCoordinate2D(latitude: geoPoint.latitude,
                                               longitude: geoPoint.longitude),
            visibility: visibility,
            reactionCount: reactionCount,
            liftCount: liftCount
        )
    }

    private func fetchDocument(_ reference: DocumentReference) async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            reference.getDocument { snapshot, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let snapshot = snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "DropStore",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Missing snapshot"]
                    ))
                }
            }
        }
    }

    private func commit(batch: WriteBatch) async throws {
        try await withCheckedThrowingContinuation { continuation in
            batch.commit { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
