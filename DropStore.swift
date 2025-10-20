import Foundation
import CoreLocation
import Combine
import MapKit
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

    func listenNearby(in region: MKCoordinateRegion) {
        let bounds = boundingBox(for: region)
        listenNearby(minLat: bounds.minLat,
                     maxLat: bounds.maxLat,
                     minLon: bounds.minLon,
                     maxLon: bounds.maxLon)
    }

    func stopListeningNearby() {
        listener?.remove()
        listener = nil
    }

    private func listenNearby(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        stopListeningNearby()

        let prefixes = Geohash.prefixesCovering(
            region: (minLat, maxLat, minLon, maxLon),
            precision: 5
        )

        guard !prefixes.isEmpty else {
            drops = []
            return
        }

        var collected: [String: DropItem] = [:]
        var registrations: [ListenerRegistration] = []

        for prefix in prefixes {
            let start = prefix
            let end = prefix + "\u{f8ff}"

            let registration = db.collection("drops")
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
                                visibility: DropVisibility(rawValue: vis) ?? .public
                            )
                            collected[item.id] = item
                        }
                    }

                    self.drops = collected.values.sorted(by: { $0.createdAt > $1.createdAt })
                }

            registrations.append(registration)
        }

        listener = ListenerToken(registrations: registrations)
    }

    private func boundingBox(for region: MKCoordinateRegion) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2

        var minLat = max(-90, region.center.latitude - halfLat)
        var maxLat = min(90, region.center.latitude + halfLat)

        var minLon = region.center.longitude - halfLon
        var maxLon = region.center.longitude + halfLon

        if minLon < -180 { minLon = -180 }
        if maxLon > 180 { maxLon = 180 }

        if minLat > maxLat {
            swap(&minLat, &maxLat)
        }
        if minLon > maxLon {
            swap(&minLon, &maxLon)
        }

        return (minLat, maxLat, minLon, maxLon)
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

private final class ListenerToken: ListenerRegistration {
    private var registrations: [ListenerRegistration]
    private var isActive = true

    init(registrations: [ListenerRegistration]) {
        self.registrations = registrations
    }

    func remove() {
        guard isActive else { return }
        isActive = false
        registrations.forEach { $0.remove() }
        registrations.removeAll()
    }
}
