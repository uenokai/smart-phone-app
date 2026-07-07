import SwiftUI

/// アプリのメイン画面ビュー
struct ContentView: View {
    @StateObject private var mapViewModel = MapViewModel()
    @StateObject private var searchViewModel = SearchViewModel()
    @State private var selectedPlace: Place? = nil
    @State private var showDetailView = false

    var body: some View {
        ZStack {
            // マップビュー
            MapView(viewModel: mapViewModel, places: mapViewModel.places)
                .ignoresSafeArea()
                .onAppear {
                    mapViewModel.startUpdatingLocation()
                }

            // 下部フィルターパネル
            VStack {
                Spacer()
                FilterPanelView(
                    searchViewModel: searchViewModel,
                    mapViewModel: mapViewModel
                )
                .frame(maxHeight: 400)
                .background(Color.white)
                .cornerRadius(16, corners: [.topLeft, .topRight])
                .shadow(radius: 10)
            }
            .ignoresSafeArea(.keyboard)

            // 結果表示
            if !mapViewModel.places.isEmpty {
                VStack {
                    HStack {
                        Text("検索結果：\(mapViewModel.places.count)件")
                            .font(.caption)
                            .padding(8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        Spacer()
                    }
                    .padding()

                    Spacer()

                    // スクロール可能な結果リスト
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(mapViewModel.places) { place in
                                PlaceCardView(place: place)
                                    .onTapGesture {
                                        selectedPlace = place
                                        showDetailView = true
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .sheet(isPresented: $showDetailView, onDismiss: {
            selectedPlace = nil
        }) {
            if let selectedPlace = selectedPlace {
                DetailView(place: selectedPlace)
            }
        }
    }
}

/// 検索結果のカード表示
struct PlaceCardView: View {
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.name)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let rating = place.rating {
                    Label("\(String(format: "%.1f", rating))", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if let priceLevel = place.priceLevel {
                    Text(String(repeating: "¥", count: priceLevel))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Text(place.address)
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(2)

            Spacer()
        }
        .padding(12)
        .frame(width: 160, height: 140)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 4)
    }
}

// MARK: - RoundedCorner Modifier

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

#Preview {
    ContentView()
}
