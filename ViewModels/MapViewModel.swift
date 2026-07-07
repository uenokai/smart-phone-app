import Foundation
import Combine
import CoreLocation

/// マップとピン表示ロジックを管理するViewModel
@MainActor
class MapViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var places: [Place] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var userLocation: CLLocationCoordinate2D? = nil
    @Published var selectedPlace: Place? = nil

    private let googlePlacesService: GooglePlacesService
    private let locationManager = CLLocationManager()

    override init() {
        self.googlePlacesService = GooglePlacesService()
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

    /// 条件と好みプロファイルに基づいてお店を検索
    /// 1. Nearby Searchで候補を取得し一次ランキング
    /// 2. 上位の候補にDetails APIで口コミ本文などを付加
    /// 3. 口コミテキストを使って好みタグ・学習タグで最終ランキング
    func searchPlaces(
        filter: SearchFilter,
        profile: TasteProfile = TasteProfile(),
        learnedTags: [String] = []
    ) async {
        isLoading = true
        error = nil

        guard let userLocation = userLocation else {
            error = "位置情報を取得できません"
            isLoading = false
            return
        }

        do {
            let results = try await googlePlacesService.searchPlaces(
                latitude: userLocation.latitude,
                longitude: userLocation.longitude,
                filter: filter
            )
            // APIが対応していない条件（最低評価など）をクライアント側で絞り込む
            let filtered = results.filter { filter.matches($0) }
            let preliminary = RecommendationEngine.rank(filtered, profile: profile, learnedTags: learnedTags)
            let enriched = await googlePlacesService.enrichPlacesWithDetails(preliminary)
            // 詳細取得で営業時間などが判明した店を再度絞り込んでから最終ランキング
            let ranked = RecommendationEngine.rank(
                enriched.filter { filter.matches($0) },
                profile: profile,
                learnedTags: learnedTags
            )
            self.places = ranked
            if ranked.isEmpty && !results.isEmpty {
                self.error = "条件に合う場所が見つかりませんでした。検索条件や「好みの設定」を緩めてみてください"
            }
        } catch {
            self.error = "検索に失敗しました：\(error.localizedDescription)"
        }

        isLoading = false
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
