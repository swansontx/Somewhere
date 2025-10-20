import SwiftUI
import AuthenticationServices
import FirebaseAuth
import CryptoKit

struct HomeView: View {
    @Binding var showCreate: Bool
    @State private var authUser: FirebaseAuth.User? = Auth.auth().currentUser  // <— use FirebaseAuth.User here
    @State private var nonce = ""

    var body: some View {
        VStack(spacing: 24) {

            if authUser == nil {
                Text("Welcome to Somewhere")
                    .font(.largeTitle).bold()
                    .padding(.top, 60)

                Text("Sign in to start dropping your thoughts.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                SignInWithAppleButton(.signIn, onRequest: configure, onCompletion: handle)
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 55)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal)
            } else {
                Text("Drop something?")
                    .font(.largeTitle).bold()
                    .padding(.top, 40)

                Text("Leave a short thought where you are. Choose who can see it: Public, Friends, or Private.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Button {
                    showCreate = true
                } label: {
                    Text("Drop Something")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.opacity(0.9))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal)

                Button("Sign out") {
                    try? Auth.auth().signOut()
                    authUser = nil
                }
                .padding(.top, 8)
                .foregroundColor(.red)

                Spacer()
            }
        }
        .onAppear { authUser = Auth.auth().currentUser }
        .animation(.easeInOut, value: authUser != nil)
    }
}

// MARK: - Sign in with Apple helpers
extension HomeView {
    private func configure(_ request: ASAuthorizationAppleIDRequest) {
        nonce = randomNonce()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authResult):
            guard
                let appleID = authResult.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = appleID.identityToken,
                let tokenString = String(data: tokenData, encoding: .utf8)
            else { return }

            // New API in recent FirebaseAuth:
            let credential = OAuthProvider.appleCredential(
                withIDToken: tokenString,
                rawNonce: nonce,
                fullName: appleID.fullName
            )

            let auth = Auth.auth()

            if let currentUser = auth.currentUser, currentUser.isAnonymous {
                currentUser.link(with: credential) { result, error in
                    if let error = error as NSError? {
                        guard error.code == AuthErrorCode.credentialAlreadyInUse.rawValue else {
                            print("Linking failed:", error.localizedDescription)
                            return
                        }

                        // The Apple credential is already in use on another account. Sign in with it instead.
                        if let updatedCredential = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential {
                            signIn(using: updatedCredential)
                        } else {
                            signIn(using: credential)
                        }
                        return
                    }

                    Task { @MainActor in
                        authUser = result?.user ?? auth.currentUser
                    }
                }
            } else {
                signIn(using: credential)
            }

        case .failure(let error):
            print("Authorization error:", error.localizedDescription)
        }
    }

    private func signIn(using credential: AuthCredential) {
        Auth.auth().signIn(with: credential) { _, error in
            if let error = error {
                print("Sign in failed:", error.localizedDescription)
                return
            }

            Task { @MainActor in
                authUser = Auth.auth().currentUser
            }
        }
    }
}

// MARK: - Crypto helpers
private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.map { String(format: "%02x", $0) }.joined()
}

private func randomNonce(length: Int = 32) -> String {
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length
    while remaining > 0 {
        let randoms = (0..<16).map { _ in UInt8.random(in: 0...255) }
        for r in randoms where remaining > 0 {
            if r < charset.count { result.append(charset[Int(r % UInt8(charset.count))]); remaining -= 1 }
        }
    }
    return result
}
