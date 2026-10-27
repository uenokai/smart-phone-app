import Foundation

/// 緯度経度。CoreLocation に依存しない形にして、ロジックとテストから扱いやすくする
struct GeoPoint: Codable, Equatable, Hashable {
    let latitude: Double
    let longitude: Double

    /// 2点間の距離（メートル）。ハバーサイン公式
    func distance(to other: GeoPoint) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }

    /// 北・東方向にメートル単位でずらした点
    func offset(northMeters: Double, eastMeters: Double) -> GeoPoint {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(latitude * .pi / 180)
        return GeoPoint(
            latitude: latitude + northMeters / metersPerDegreeLat,
            longitude: longitude + eastMeters / max(metersPerDegreeLon, 1)
        )
    }
}
