import SwiftUI

/// ピンをタップしたときに表示される詳細情報ビュー
/// 判定理由の内訳とネット上の言及を見せて、「なぜこの店が有益と判断されたか」を利用者が検証できるようにする
struct DetailView: View {
    let place: Place
    /// 検索結果から開いた場合の採点（お気に入りから開いた場合は nil）
    var scored: ScoredPlace? = nil
    var placesService: GooglePlacesService = GooglePlacesService()

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var favoritesViewModel: FavoritesViewModel
    @EnvironmentObject var knownPlacesViewModel: KnownPlacesViewModel
    @State private var showLoginSheet = false
    @State private var photoURL: URL? = nil

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    photoSection
                    headerSection
                    if let scored = scored {
                        reasonsSection(scored)
                    }
                    if let mentions = place.webMentions {
                        webMentionsSection(mentions)
                    }
                    basicInfoSection
                    openingHoursSection
                    reviewsSection
                    knownSection
                    actionsSection
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showLoginSheet) {
                LoginView(authViewModel: authViewModel)
            }
            .task {
                guard let name = place.photoName, placesService.isConfigured else { return }
                photoURL = try? await placesService.fetchPhotoURL(photoName: name, maxWidthPx: 800)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var photoSection: some View {
        if let photoURL = photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Color.gray.opacity(0.1)
                default:
                    ZStack {
                        Color.gray.opacity(0.1)
                        ProgressView()
                    }
                }
            }
            .frame(height: 200)
            .clipped()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(place.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                // お気に入りボタン（会員限定機能）
                Button(action: {
                    if authViewModel.isSignedIn {
                        favoritesViewModel.toggleFavorite(place)
                    } else {
                        showLoginSheet = true
                    }
                }) {
                    Image(systemName: favoritesViewModel.isFavorite(place) ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundColor(.pink)
                }
            }

            HStack(spacing: 12) {
                if let label = scored?.badge.label {
                    Text(label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(8)
                }

                if let rating = place.rating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", rating))
                            .font(.caption)
                        if let reviews = place.userRatingsTotal {
                            Text("(口コミ\(reviews)件)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }

                if let priceLevel = place.priceLevel {
                    Text(String(repeating: "¥", count: priceLevel))
                        .font(.caption)
                        .padding(4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }

                Text(place.category.label)
                    .font(.caption)
                    .padding(4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)

                Spacer()
            }

            if let summary = place.editorialSummary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let status = knownPlacesViewModel.status(of: place.id) {
                Label("記録済み：\(status.label)", systemImage: status.systemImage)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    /// 判定理由の内訳
    private func reasonsSection(_ scored: ScoredPlace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("判定の内訳", systemImage: "list.bullet.clipboard")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "総合 %.2f", scored.total))
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            ForEach(scored.reasons) { reason in
                HStack(alignment: .top, spacing: 8) {
                    Text(deltaText(reason.delta))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(reason.delta > 0.0001 ? .green : (reason.delta < -0.0001 ? .red : .gray))
                        .frame(width: 48, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reason.label)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(reason.detail)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
            }

            Text("品質は口コミ数で補正した評価、未知度は今回の候補の中での口コミ数の相対位置です。PR・広告・招待の口コミは評価に使っていません。")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.purple.opacity(0.06))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    /// ネット上の言及
    private func webMentionsSection(_ mentions: WebMentionSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ネット上の言及", systemImage: "network")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(mentionCountsText(mentions))
                .font(.caption2)
                .foregroundColor(.gray)

            ForEach(mentions.listingRatings, id: \.url) { rating in
                HStack(spacing: 6) {
                    Image(systemName: "star.circle")
                        .foregroundColor(.orange)
                    Text("\(rating.site) \(String(format: "%.2f", rating.score))点" + (rating.reviewCount.map { "（口コミ\($0)件）" } ?? ""))
                        .font(.caption)
                }
            }

            if mentions.mentions.isEmpty {
                Text("「\(mentions.query)」で検索しましたが、この店に触れたページは見つかりませんでした")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                ForEach(mentions.mentions) { mention in
                    if let url = URL(string: mention.url) {
                        Link(destination: url) {
                            HStack(alignment: .top, spacing: 8) {
                                Text(mention.kind.label)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(mentionColor(mention.kind).opacity(0.15))
                                    .foregroundColor(mentionColor(mention.kind))
                                    .cornerRadius(4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mention.title)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                    Text(mention.domain)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.teal.opacity(0.06))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                Text(place.address)
                    .font(.caption)
            }

            if let phoneNumber = place.phoneNumber {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text(phoneNumber)
                        .font(.caption)
                }
            }

            if let website = place.website, let url = URL(string: website) {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Link(destination: url) {
                        Text("ウェブサイト")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var openingHoursSection: some View {
        if let openingHours = place.openingHours {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.blue)
                    Text("営業時間")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(openingHours.isOpen ? "営業中" : "営業時間外")
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
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var reviewsSection: some View {
        if let details = place.reviewDetails, !details.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Googleの口コミ（取得できた\(details.count)件）")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ForEach(Array(details.enumerated()), id: \.offset) { _, review in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if let rating = review.rating {
                                Text(String(repeating: "★", count: max(0, min(5, rating))))
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            if let date = review.publishedAt {
                                Text(date, style: .date)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            if review.isSuspected {
                                Text("招待・PRの可能性（評価に不使用）")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                        Text(review.text)
                            .font(.caption)
                            .lineLimit(4)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal)
        } else if let reviews = place.reviews, !reviews.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("レビュー")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                ForEach(reviews.prefix(3), id: \.self) { review in
                    Text(review)
                        .font(.caption)
                        .lineLimit(3)
                        .padding(8)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal)
        }
    }

    /// 既知の記録（以後の検索結果から外す）
    private var knownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("この店を知っていましたか？")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("記録した店は以後の検索結果に出なくなります（もう一度押すと取り消し）")
                .font(.caption2)
                .foregroundColor(.gray)
            HStack(spacing: 8) {
                ForEach(KnownPlace.Status.allCases, id: \.self) { status in
                    let isSelected = knownPlacesViewModel.status(of: place.id) == status
                    Button(action: { knownPlacesViewModel.toggle(place, status: status) }) {
                        Label(status.label, systemImage: status.systemImage)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.blue : Color.gray.opacity(0.15))
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }

    private var actionsSection: some View {
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
               let url = URL(string: "tel://\(phoneNumber.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: ""))") {
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
    }

    // MARK: - Helpers

    private func deltaText(_ delta: Double) -> String {
        if abs(delta) < 0.0001 { return "±0" }
        return (delta > 0 ? "+" : "−") + String(format: "%.2f", abs(delta))
    }

    private func mentionCountsText(_ mentions: WebMentionSummary) -> String {
        var parts: [String] = []
        parts.append("本物の口コミ \(mentions.genuineCount)件")
        if mentions.mediaCount > 0 { parts.append("メディア \(mentions.mediaCount)件") }
        if mentions.listingCount > 0 { parts.append("掲載サイト \(mentions.listingCount)件") }
        if mentions.promotionalCount > 0 { parts.append("PR・広告 \(mentions.promotionalCount)件（評価に不使用）") }
        return parts.joined(separator: "・")
    }

    private func mentionColor(_ kind: WebMention.Kind) -> Color {
        switch kind {
        case .genuine: return .teal
        case .media: return .orange
        case .listing: return .gray
        case .promotional: return .red
        case .official: return .blue
        case .other: return .gray
        }
    }

    private func buildGoogleMapsURL() -> URL {
        if let link = place.googleMapsURL, let url = URL(string: link) {
            return url
        }
        return URL(string: "https://maps.google.com/?q=\(place.latitude),\(place.longitude)") ?? URL(fileURLWithPath: "")
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
            userRatingsTotal: 42,
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
    .environmentObject(AuthViewModel())
    .environmentObject(FavoritesViewModel())
    .environmentObject(KnownPlacesViewModel())
}
