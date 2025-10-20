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

    private var listeners: [ListenerRegistration] = []
    private var dropCache: [String: DropItem] = [:]
    private(set) var lastBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)?

    init() {
        Task { await ensureSignedIn() }
    }

    deinit {
        stopListening()
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
            "geohash": geohash
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
        stopListening()
        dropCache.removeAll()
        lastBounds = (minLat, maxLat, minLon, maxLon)

        let prefixes = Geohash.prefixesCovering(
            region: (minLat, maxLat, minLon, maxLon),
            precision: 5
        )

        guard !prefixes.isEmpty else {
            drops.removeAll()
            return
        }

        for prefix in prefixes {
            let start = prefix
            let end = prefix + "\u{f8ff}"

            let registration = db.collection("drops")
                .order(by: "geohash")
                .start(at: [start])
                .end(at: [end])
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self else { return }

                    Task { @MainActor in
                        if let error {
                            print("Firestore listener error:", error.localizedDescription)
                            return
                        }

                        guard let snapshot else { return }

                        for change in snapshot.documentChanges {
                            let doc = change.document
                            switch change.type {
                            case .added, .modified:
                                if let item = self.makeDropItem(from: doc) {
                                    self.dropCache[item.id] = item
                                }
                            case .removed:
                                self.dropCache.removeValue(forKey: doc.documentID)
                            @unknown default:
                                break
                            }
                        }

                        self.drops = self.dropCache.values.sorted(by: { $0.createdAt > $1.createdAt })
                    }
                }

            listeners.append(registration)
        }
    }

    func refreshNearby() {
        guard let bounds = lastBounds else { return }
        listenNearby(minLat: bounds.minLat, maxLat: bounds.maxLat, minLon: bounds.minLon, maxLon: bounds.maxLon)
    }

    private func makeDropItem(from doc: QueryDocumentSnapshot) -> DropItem? {
        let data = doc.data()
        guard
            let text = data["text"] as? String,
            let visibilityRaw = data["visibility"] as? String,
            let location = data["location"] as? GeoPoint
        else { return nil }

        return DropItem(
            id: doc.documentID,
            text: text,
            author: User(id: data["authorId"] as? String ?? "unknown",
                         name: "Unknown"),
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            coordinate: CLLocationCoordinate2D(latitude: location.latitude,
                                               longitude: location.longitude),
            visibility: DropVisibility(rawValue: visibilityRaw) ?? .public
        )
    }

    func stopListening() {
        for listener in listeners {
            listener.remove()
        }
        listeners.removeAll()
        dropCache.removeAll()
        lastBounds = nil
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
        if let i = drops.firstIndex(where: { $0.id == drop.id }) {
            drops[i].reactions += 1
        }
    }
}
