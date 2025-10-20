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
    @Published var isUsingAnonymousAccount: Bool = true
    @Published var authError: String? = nil
    @Published var drops: [DropItem] = []
    @Published var lifted: Set<String> = []

    private var listener: ListenerRegistration?
    private var authListener: AuthStateDidChangeListenerHandle?

    init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.updateCurrentUser(with: user)
        }
        ensureSignedIn()
    }

    deinit {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }

    // MARK: - Authentication Handling

    /// Ensures there's a Firebase Auth user (Apple or anonymous)
    func ensureSignedIn() {
        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { [weak self] result, error in
                guard let self else { return }
                if let error {
                    print("Anonymous sign-in failed:", error.localizedDescription)
                    self.authError = error.localizedDescription
                    self.updateCurrentUser(with: nil)
                } else if let user = result?.user {
                    print("Signed in anonymously as \(user.uid)")
                    self.authError = nil
                    self.updateCurrentUser(with: user)
                }
            }
        } else {
            authError = nil
            updateCurrentUser(with: Auth.auth().currentUser)
        }
    }

    /// Signs the user out completely (forces re-auth next launch)
    func signOut() {
        do {
            try Auth.auth().signOut()
            listener?.remove()
            listener = nil
            currentUser = nil
            drops.removeAll()
            lifted.removeAll()
            isUsingAnonymousAccount = true
            authError = nil
        } catch {
            print("Error signing out:", error.localizedDescription)
            authError = error.localizedDescription
        }
        ensureSignedIn()
    }

    func signInWithApple(idToken: String, nonce: String, fullName: PersonNameComponents?) {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: fullName
        )

        let auth = Auth.auth()
        let finish: (AuthDataResult?, Error?) -> Void = { [weak self] result, error in
            guard let self else { return }

            if let error {
                print("Sign in failed:", error.localizedDescription)
                self.authError = error.localizedDescription
                return
            }

            if let user = result?.user ?? auth.currentUser {
                self.authError = nil
                self.applyDisplayNameIfNeeded(fullName, to: user)
                self.updateCurrentUser(with: user)
            }
        }

        if let current = auth.currentUser, current.isAnonymous {
            current.link(with: credential) { result, error in
                if let error = error as NSError?,
                   error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                    auth.signIn(with: credential) { result, error in
                        if error == nil {
                            current.delete(completion: nil)
                        }
                        finish(result, error)
                    }
                } else {
                    finish(result, error)
                }
            }
        } else {
            auth.signIn(with: credential, completion: finish)
        }
    }

    private func updateCurrentUser(with authUser: FirebaseAuth.User?) {
        guard let authUser else {
            currentUser = nil
            isUsingAnonymousAccount = true
            return
        }

        isUsingAnonymousAccount = authUser.isAnonymous
        let displayName = authUser.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        currentUser = User(id: authUser.uid,
                           name: (displayName?.isEmpty == false ? displayName! : "Guest"))
    }

    private func applyDisplayNameIfNeeded(_ fullName: PersonNameComponents?,
                                          to user: FirebaseAuth.User) {
        guard let fullName else { return }

        let formatter = PersonNameComponentsFormatter()
        let displayName = formatter.string(from: fullName)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !displayName.isEmpty, user.displayName != displayName else { return }

        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = displayName
        changeRequest.commitChanges { [weak self] error in
            if let error {
                print("Failed to update display name:", error.localizedDescription)
                self?.authError = error.localizedDescription
            } else {
                self?.authError = nil
                self?.updateCurrentUser(with: user)
            }
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
                                visibility: DropVisibility(rawValue: vis) ?? .public
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
        if let i = drops.firstIndex(where: { $0.id == drop.id }) {
            drops[i].reactions += 1
        }
    }
}
