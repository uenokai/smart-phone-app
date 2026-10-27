import Foundation
import Combine
import CoreLocation

/// 検索1回の要約（候補の集め方と使った情報源を利用者に見せる）
struct SearchSummary: Equatable {
    /// 範囲内で集まった候補数（除外前）
    let candidateCount: Int
    /// 表示している件数
    let shownCount: Int
    /// Places API の検索呼び出し回数
    let apiCalls: Int
    /// 20件で打ち切られた円の数（0でなければ取りこぼしの可能性あり）
    let saturatedTiles: Int
    /// 口コミ本文を取得した件数
    let detailedCount: Int
    /// ネット言及を調べた件数（Brave Search API 未設定なら nil）
    let webMentionCount: Int?

    var text: String {
        var parts = ["候補\(candidateCount)件（検索\(apiCalls)回）"]
        if saturatedTiles > 0 {
            parts.append("取りこぼしの可能性あり")
        }
        if let web = webMentionCount {
            parts.append("ネット言及\(web)件を確認")
        } else {
            parts.append("ネット言及は未設定")
        }
        return parts.joined(separator: "・")
    }
}

/// マップとピン表示ロジックを管理するViewModel
@MainActor
class MapViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var results: [ScoredPlace] = []
    @Published var isLoading: Bool = false
    /// 検索中の進捗表示
    @Published var progress: String? = nil
    @Published var error: String? = nil
    @Published var userLocation: CLLocationCoordinate2D? = nil
    @Published var selectedResult: ScoredPlace? = nil
    /// 現在表示中の地図の中心（地図を動かした場所で検索できるようにする）
    @Published var mapCenter: CLLocationCoordinate2D? = nil
    @Published var searchSummary: SearchSummary? = nil

    /// 結果として表示する最大件数
    static let maxShownResults = 30
    /// 口コミ本文を取得する件数（Place Details の呼び出し回数）
    static let detailLimit = 15
    /// ネット言及を調べる件数（Brave Search の呼び出し回数）
    static let webMentionLimit = 10

    let placesService: GooglePlacesService
    private let webMentionService: WebMentionService?
    private let locationManager = CLLocationManager()

    /// ピン表示用
    var places: [Place] { results.map { $0.place } }

    /// Brave Search API キーが設定されているか
    var isWebMentionAvailable: Bool { webMentionService != nil }

    override init() {
        self.placesService = GooglePlacesService()
        let brave = BraveSearchClient()
        self.webMentionService = brave.isConfigured ? WebMentionService(client: brave) : nil
        super.init()
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.requestWhenInUseAuthorization()
    }

    /// ユーザーの位置情報を更新
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }

    /// ピンタップ時に該当するお店を選択する
    func selectPlace(id: String) {
        selectedResult = results.first { $0.id == id }
    }

    /// 条件と好みプロファイルに基づいてお店を検索
    /// 1. 範囲を小さな円に分けて距離順に候補を集める（人気順の上位20件に偏らない）
    /// 2. クライアント側の条件で絞り込み、一次採点
    /// 3. 上位に Place Details で口コミ本文・投稿日を付加
    /// 4. 上位のネット言及（ブログ・SNS）を検索し、PR・広告を除いて集計
    /// 5. 候補全体の統計を使って最終採点・並べ替え
    func searchPlaces(
        filter: SearchFilter,
        profile: TasteProfile = TasteProfile(),
        learnedTags: [String] = [],
        knownIds: Set<String> = []
    ) async {
        isLoading = true
        error = nil
        progress = nil

        // 地図を動かしていればその中心、そうでなければ現在地を検索起点にする
        guard let origin = mapCenter ?? userLocation else {
            error = "位置情報を取得できません"
            isLoading = false
            return
        }
        guard placesService.isConfigured else {
            error = PlacesAPIError.missingAPIKey.localizedDescription
            isLoading = false
            return
        }

        let center = GeoPoint(latitude: origin.latitude, longitude: origin.longitude)
        let types = filter.categories.flatMap { $0.includedTypes }
        let maxCalls = filter.thoroughness.maxAPICalls

        progress = "候補を集めています（最大\(maxCalls)回検索）"
        let collector = CandidateCollector(client: placesService)
        let collected = await collector.collect(
            center: center,
            radiusMeters: filter.maxDistance * 1000,
            types: types.isEmpty ? ["restaurant"] : types,
            maxCalls: maxCalls
        )

        if collected.places.isEmpty {
            if let collectError = collected.error {
                self.error = "検索に失敗しました：\(collectError.localizedDescription)"
            } else {
                self.error = "この範囲には該当する場所がありません"
            }
            results = []
            searchSummary = nil
            isLoading = false
            progress = nil
            return
        }

        // API が対応していない条件（価格帯・最低評価・営業中）をクライアント側で絞り込む
        let filtered = collected.places.filter { filter.matches($0) }
        let excluded: Set<String> = profile.hideKnownPlaces ? knownIds : Set<String>()

        // 一次採点（評価・未知度・チェーン判定のみ）
        let preliminary = RecommendationEngine.evaluate(
            filtered, profile: profile, learnedTags: learnedTags, knownIds: excluded
        )

        // 上位に口コミ本文・投稿日を付加
        progress = "口コミを確認しています（\(min(Self.detailLimit, preliminary.count))件）"
        let topPlaces = preliminary.prefix(Self.detailLimit).map { $0.place }
        var enriched = await placesService.enrichPlacesWithDetails(topPlaces, limit: Self.detailLimit)

        // ネット上の本物の口コミを集計
        var webMentionCount: Int? = nil
        if profile.useWebMentions, let webMentionService = webMentionService {
            let targets = Array(enriched.prefix(Self.webMentionLimit))
            progress = "ネット上の口コミを調べています（\(targets.count)件）"
            let summaries = await webMentionService.summaries(for: targets)
            for index in enriched.indices {
                if let summary = summaries[enriched[index].id] {
                    enriched[index].webMentions = summary
                }
            }
            webMentionCount = summaries.count
        }

        // 候補全体（詳細未取得の店も含む）の統計で最終採点する
        let enrichedIds = Set(enriched.map { $0.id })
        let rest = preliminary.map { $0.place }.filter { !enrichedIds.contains($0.id) }
        let finalPool = (enriched + rest).filter { filter.matches($0) }
        let ranked = RecommendationEngine.evaluate(
            finalPool, profile: profile, learnedTags: learnedTags, knownIds: excluded
        )

        results = Array(ranked.prefix(Self.maxShownResults))
        searchSummary = SearchSummary(
            candidateCount: collected.places.count,
            shownCount: results.count,
            apiCalls: collected.apiCalls,
            saturatedTiles: collected.saturatedTiles,
            detailedCount: enriched.count,
            webMentionCount: webMentionCount
        )
        if results.isEmpty {
            self.error = "条件に合う場所が見つかりませんでした。検索条件や「好みの設定」を緩めてみてください"
        }

        isLoading = false
        progress = nil
    }

    /// CLLocationManagerDelegate
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.userLocation = location.coordinate
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.error = "位置情報エラー：\(error.localizedDescription)"
        }
    }
}
