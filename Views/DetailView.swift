import SwiftUI

/// ピンをタップしたときに表示される詳細情報ビュー
struct DetailView: View {
    let place: Place
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ヘッダー
                    VStack(alignment: .leading, spacing: 8) {
                        Text(place.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        HStack(spacing: 12) {
                            // 評価
                            if let rating = place.rating {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                    Text(String(format: "%.1f", rating))
                                        .font(.caption)
                                }
                            }

                            // 価格帯
                            if let priceLevel = place.priceLevel {
                                Text(priceText(priceLevel))
                                    .font(.caption)
                                    .padding(4)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            }

                            // カテゴリ
                            Text(categoryLabel(place.category))
                                .font(.caption)
                                .padding(4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)

                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)

                    // 基本情報
                    VStack(alignment: .leading, spacing: 12) {
                        // 住所
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            Text(place.address)
                                .font(.caption)
                        }

                        // 電話番号
                        if let phoneNumber = place.phoneNumber {
                            HStack(spacing: 12) {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 20)
                                Text(phoneNumber)
                                    .font(.caption)
                            }
                        }

                        // ウェブサイト
                        if let website = place.website {
                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .foregroundColor(.blue)
                                    .frame(width: 20)
                                Link(destination: URL(string: website) ?? URL(fileURLWithPath: "")) {
                                    Text("ウェブサイト")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .padding()

                    // 営業時間
                    if let openingHours = place.openingHours {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(.blue)
                                Text("営業時間")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(openingHours.isOpen ? "営業中" : "営業終了")
                                    .font(.caption)
                                    .foregroundColor(openingHours.isOpen ? .green : .red)
                            }

                            if let weekdays = openingHours.weekday {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(weekdays, id: \.self) { day in
                                        Text(day)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)
                    }

                    // レビュー
                    if let reviews = place.reviews, !reviews.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("レビュー")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(reviews.prefix(3), id: \.self) { review in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(review)
                                            .font(.caption)
                                            .lineLimit(2)
                                    }
                                    .padding(8)
                                    .background(Color.gray.opacity(0.05))
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .padding()
                    }

                    // アクションボタン
                    VStack(spacing: 10) {
                        Link(destination: buildGoogleMapsURL()) {
                            HStack {
                                Image(systemName: "map.fill")
                                Text("Google Maps で表示")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }

                        if let phoneNumber = place.phoneNumber,
                           let url = URL(string: "tel://\(phoneNumber.replacingOccurrences(of: "-", with: ""))") {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "phone.fill")
                                    Text("電話する")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func priceText(_ level: Int) -> String {
        String(repeating: "¥", count: level)
    }

    private func categoryLabel(_ category: Place.PlaceCategory) -> String {
        switch category {
        case .restaurant: return "レストラン"
        case .cafe: return "カフェ"
        case .bar: return "バー"
        case .touristAttraction: return "観光地"
        case .museum: return "博物館"
        case .park: return "公園"
        }
    }

    private func buildGoogleMapsURL() -> URL {
        let latitude = place.latitude
        let longitude = place.longitude
        let url = URL(string: "https://maps.google.com/?q=\(latitude),\(longitude)") ?? URL(fileURLWithPath: "")
        return url
    }
}

#Preview {
    DetailView(
        place: Place(
            id: "1",
            name: "Sample Restaurant",
            category: .restaurant,
            latitude: 35.6762,
            longitude: 139.7674,
            address: "Tokyo, Japan",
            priceLevel: 2,
            rating: 4.5,
            openingHours: OpeningHours(
                isOpen: true,
                weekday: ["月 11:00-23:00", "火 11:00-23:00"],
                nextOpeningTime: nil,
                nextClosingTime: nil
            ),
            website: "https://example.com",
            phoneNumber: "03-1234-5678",
            reviews: ["美味しいお店です", "雰囲気がいい"]
        )
    )
}
