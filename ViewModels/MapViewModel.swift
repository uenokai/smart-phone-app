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
    /// 取得結果はRecommendationEngineで「穴場度」と好みの一致度により並べ替える
    func searchPlaces(filter: SearchFilter, profile: TasteProfile = TasteProfile()) async {
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
            let ranked = RecommendationEngine.rank(results, profile: profile)
            self.places = ranked
            if ranked.isEmpty && !results.isEmpty {
                self.error = "好みの条件に合う場所が見つかりませんでした。「好みの設定」を緩めてみてください"
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
