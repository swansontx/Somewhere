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
    @Published var lifted: Set<String> = []

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

        let dropRef = db.collection("drops").document()
        let userRef = db.collection("users").document(user.uid)
        let now = Timestamp(date: Date())

        let data: [String: Any] = [
            "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
            "authorId": user.uid,
            "createdAt": now,
            "visibility": visibility.rawValue,
            "location": GeoPoint(latitude: coordinate.latitude,
                                 longitude: coordinate.longitude),
            "geohash": geohash,
            "reactionsCount": 0
        ]

        db.runTransaction({ (transaction, errorPointer) -> Any? in
            transaction.setData(data, forDocument: dropRef)

            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(userRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }

            var stats = snapshot.data()?["stats"] as? [String: Any] ?? [:]
            let currentCount = (stats["dropsCount"] as? Int ?? 0) + 1
            stats["dropsCount"] = currentCount
            stats["lastDropAt"] = now
            stats["lastEngagedAt"] = now

            transaction.setData(["stats": stats], forDocument: userRef, merge: true)
            return dropRef.documentID
        }) { _, error in
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
                            let d = doc.data()
                            guard
                                let text = d["text"] as? String,
                                let vis = d["visibility"] as? String,
                                let geo = d["location"] as? GeoPoint
                            else { continue }

                            let item = DropItem(
                                id: doc.documentID,
                                text: text,
                                author: User(id: d["authorId"] as? String ?? "unknown",
                                             name: "Unknown"),
                                createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? .now,
                                coordinate: CLLocationCoordinate2D(latitude: geo.latitude,
                                                                   longitude: geo.longitude),
                                visibility: DropVisibility(rawValue: vis) ?? .public,
                                reactions: d["reactionsCount"] as? Int ?? 0
                            )
                            collected[item.id] = item
                        }
                    }

                    self.drops = collected.values.sorted(by: { $0.createdAt > $1.createdAt })
                }
        }
    }

    // MARK: - Reactions & Lifts (Local Only for Now)

    func toggleLift(_ drop: DropItem) {
        if lifted.contains(drop.id) {
            lifted.remove(drop.id)
        } else {
            lifted.insert(drop.id)
        }
        if let i = drops.firstIndex(where: { $0.id == drop.id }) {
            drops[i].isLiftedByCurrentUser = lifted.contains(drop.id)
        }
    }

    func react(to drop: DropItem) {
        let dropRef = db.collection("drops").document(drop.id)
        dropRef.updateData(["reactionsCount": FieldValue.increment(Int64(1))]) { [weak self] error in
            if let error = error {
                print("Error recording reaction:", error.localizedDescription)
                return
            }

            Task { @MainActor in
                guard let self else { return }
                if let index = self.drops.firstIndex(where: { $0.id == drop.id }) {
                    self.drops[index].reactions += 1
                }
            }
        }
    }
}
