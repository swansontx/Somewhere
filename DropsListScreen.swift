import SwiftUI
import MapKit

struct DropsListScreen: View {
    @EnvironmentObject var store: DropStore

    var body: some View {
        NavigationStack {
            List(store.drops) { drop in
                VStack(alignment: .leading, spacing: 6) {
                    Text(drop.text).font(.headline)
                    Text("\(drop.author.name) • \(drop.visibility.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if case .pending = drop.syncStatus {
                        Text("Sending…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if case let .failed(message) = drop.syncStatus {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Couldn't send drop")
                                .font(.footnote)
                                .foregroundColor(.red)
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Button("Retry") {
                                store.retryCreate(drop: drop)
                            }
                            .font(.footnote.weight(.semibold))
                        }
                    }
                }
            }
            .navigationTitle("Drops")
            .refreshable {
                if store.lastBounds != nil {
                    store.refreshNearby()
                } else {
                    requestDefaultRegion()
                }
            }
            .overlay {
                if store.drops.isEmpty {
                    ContentUnavailableView("No drops yet", systemImage: "cloud.sun") {
                        Text("Pull to refresh to try again.")
                    }
                }
            }
        }
        .task {
            guard store.lastBounds == nil else { return }
            requestDefaultRegion()
        }
    }

    private func requestDefaultRegion() {
        let center = CLLocationCoordinate2D(latitude: 37.775, longitude: -122.418)
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let halfLat = max(span.latitudeDelta / 2, 0.002)
        let halfLon = max(span.longitudeDelta / 2, 0.002)

        let minLat = max(-90, center.latitude - halfLat)
        let maxLat = min(90, center.latitude + halfLat)
        let minLon = max(-180, center.longitude - halfLon)
        let maxLon = min(180, center.longitude + halfLon)

        store.listenNearby(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }
}
