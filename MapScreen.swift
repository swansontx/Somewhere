import SwiftUI
import MapKit

struct MapScreen: View {
    @EnvironmentObject var store: DropStore
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.775, longitude: -122.418),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var selectedDrop: DropItem?
    @Binding var lastTappedLocation: CLLocationCoordinate2D
    @State private var lastQueriedRegion: MKCoordinateRegion?

    var onRequestCreateAt: (CLLocationCoordinate2D) -> Void

    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, annotationItems: store.drops) { drop in
                MapAnnotation(coordinate: drop.coordinate) {
                    Button {
                        selectedDrop = drop
                    } label: {
                        Circle()
                            .fill(color(for: drop.visibility).opacity(0.9))
                            .frame(width: 16, height: 16)
                            .shadow(radius: 2)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        onRequestCreateAt(region.center)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.bold())
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 3)
                    }
                    .padding()
                }
            }
        }
        .sheet(item: $selectedDrop) { drop in
            DropDetailScreen(drop: drop)
        }
        .onAppear { updateListener(for: region) }
        .onChange(of: region.center.latitude) { _ in updateListener(for: region) }
        .onChange(of: region.center.longitude) { _ in updateListener(for: region) }
        .onChange(of: region.span.latitudeDelta) { _ in updateListener(for: region) }
        .onChange(of: region.span.longitudeDelta) { _ in updateListener(for: region) }
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { _ in
                    onRequestCreateAt(region.center)
                }
        )
    }

    private func color(for vis: DropVisibility) -> Color {
        switch vis {
        case .public: return .blue
        case .friends: return .green
        case .private: return .purple
        }
    }

    private func updateListener(for region: MKCoordinateRegion) {
        guard shouldRefreshListener(for: region) else { return }
        lastQueriedRegion = region

        let halfLat = max(region.span.latitudeDelta / 2, 0.002)
        let halfLon = max(region.span.longitudeDelta / 2, 0.002)

        let minLat = max(-90, region.center.latitude - halfLat)
        let maxLat = min(90, region.center.latitude + halfLat)
        let minLon = max(-180, region.center.longitude - halfLon)
        let maxLon = min(180, region.center.longitude + halfLon)

        store.listenNearby(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    private func shouldRefreshListener(for newRegion: MKCoordinateRegion) -> Bool {
        guard let last = lastQueriedRegion else { return true }

        let centerLatDiff = abs(last.center.latitude - newRegion.center.latitude)
        let centerLonDiff = abs(last.center.longitude - newRegion.center.longitude)
        let spanLatDiff = abs(last.span.latitudeDelta - newRegion.span.latitudeDelta)
        let spanLonDiff = abs(last.span.longitudeDelta - newRegion.span.longitudeDelta)

        let latThreshold = max(newRegion.span.latitudeDelta / 4, 0.001)
        let lonThreshold = max(newRegion.span.longitudeDelta / 4, 0.001)

        let spanLatThreshold = max(last.span.latitudeDelta * 0.25, 0.002)
        let spanLonThreshold = max(last.span.longitudeDelta * 0.25, 0.002)

        return centerLatDiff > latThreshold ||
            centerLonDiff > lonThreshold ||
            spanLatDiff > spanLatThreshold ||
            spanLonDiff > spanLonThreshold
    }
}
