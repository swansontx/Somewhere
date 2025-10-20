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

        let data: [String: Any] = [
            "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
            "authorId": user.uid,
            "createdAt": Timestamp(date: Date()),
            "visibility": visibility.rawValue,
            "location": GeoPoint(latitude: coordinate.latitude,
                                 longitude: coordinate.longitude),
            "geohash": geohash,
            // aggregate engagement counters (kept in sync transactionally)
            "reactions": 0,
            "lifts": 0
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
                                reactions: d["reactions"] as? Int ?? 0,
                                isLiftedByCurrentUser: self.lifted.contains(doc.documentID)
                            )
                            collected[item.id] = item

                            if let userId = self.currentUser?.id ?? Auth.auth().currentUser?.uid {
                                self.refreshLiftState(for: doc.reference, dropId: doc.documentID, userId: userId)
                            }
                        }
                    }

                    self.drops = collected.values.sorted(by: { $0.createdAt > $1.createdAt })
                }
        }
    }

    // MARK: - Reactions & Lifts

    func toggleLift(_ drop: DropItem) {
        guard let userId = currentUser?.id ?? Auth.auth().currentUser?.uid else {
            print("User not signed in")
            return
        }

        let dropRef = db.collection("drops").document(drop.id)
        let engagementRef = dropRef.collection("engagements").document(userId)

        db.runTransaction({ transaction, errorPointer -> Any? in
            do {
                _ = try transaction.getDocument(dropRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            let engagementSnapshot: DocumentSnapshot
            do {
                engagementSnapshot = try transaction.getDocument(engagementRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            let currentlyLifted = (engagementSnapshot.data()?["lifted"] as? Bool) ?? false

            if currentlyLifted {
                transaction.updateData(["lifts": FieldValue.increment(Int64(-1))], forDocument: dropRef)
                transaction.deleteDocument(engagementRef)
                return false
            } else {
                transaction.updateData(["lifts": FieldValue.increment(Int64(1))], forDocument: dropRef)
                transaction.setData([
                    "lifted": true,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: engagementRef, merge: true)
                return true
            }
        }, completion: { [weak self] result, error in
            guard let self else { return }
            if let error = error {
                print("Failed to toggle lift:", error.localizedDescription)
                return
            }

            let isLifted = (result as? Bool) ?? false
            Task { @MainActor in
                if isLifted {
                    self.lifted.insert(drop.id)
                } else {
                    self.lifted.remove(drop.id)
                }

                if let index = self.drops.firstIndex(where: { $0.id == drop.id }) {
                    self.drops[index].isLiftedByCurrentUser = isLifted
                }
            }
        })
    }

    func react(to drop: DropItem) {
        guard let userId = currentUser?.id ?? Auth.auth().currentUser?.uid else {
            print("User not signed in")
            return
        }

        let dropRef = db.collection("drops").document(drop.id)
        let engagementRef = dropRef.collection("engagements").document(userId)

        db.runTransaction({ transaction, errorPointer -> Any? in
            do {
                _ = try transaction.getDocument(dropRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            transaction.updateData(["reactions": FieldValue.increment(Int64(1))], forDocument: dropRef)
            transaction.setData([
                "reactionCount": FieldValue.increment(Int64(1)),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: engagementRef, merge: true)

            return nil
        }, completion: { [weak self] _, error in
            guard let self else { return }
            if let error = error {
                print("Failed to react:", error.localizedDescription)
                return
            }

            Task { @MainActor in
                if let index = self.drops.firstIndex(where: { $0.id == drop.id }) {
                    self.drops[index].reactions += 1
                }
            }
        })
    }

    private func refreshLiftState(for dropRef: DocumentReference, dropId: String, userId: String) {
        dropRef.collection("engagements").document(userId).getDocument { [weak self] snapshot, error in
            guard let self else { return }
            if let error = error {
                print("Failed to refresh lift state:", error.localizedDescription)
                return
            }

            let isLifted = (snapshot?.data()?["lifted"] as? Bool) ?? false

            Task { @MainActor in
                if isLifted {
                    self.lifted.insert(dropId)
                } else {
                    self.lifted.remove(dropId)
                }

                if let index = self.drops.firstIndex(where: { $0.id == dropId }) {
                    self.drops[index].isLiftedByCurrentUser = isLifted
                }
            }
        }
    }
}
