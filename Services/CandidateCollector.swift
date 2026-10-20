import Foundation

/// 検索範囲を小さな円に分け、各円を「距離順」で取得して候補を集める
///
/// Nearby Search は1回につき最大20件しか返さず、既定の並び（POPULARITY）では人気店の上位20件だけが返る。
/// このアプリの目的は「人気順では出てこない店」を知ることなので、範囲を分割して距離順（人気と無関係な順）で取り、
/// 20件で打ち切られた円（まだ店が残っている可能性が高い円）は、呼び出し回数の余裕がある限りさらに4分割する。
struct CandidateCollector {
    let client: PlacesSearching

    /// 検索する円
    struct Tile: Equatable {
        let center: GeoPoint
        let radius: Double
    }

    struct Result {
        /// 重複を除き、指定範囲内に収まる候補
        let places: [Place]
        /// 実際に使ったAPI呼び出し回数
        let apiCalls: Int
        /// 20件で打ち切られた円の数（0でなければ取りこぼしがあり得る）
        let saturatedTiles: Int
        /// 最初の呼び出しで起きたエラー（APIキー未設定など）
        let error: Error?
    }

    /// 1回の呼び出しで返る最大件数（API仕様）
    static let pageLimit = 20
    /// これより小さい円は分割しない（メートル）
    static let minTileRadius = 120.0

    /// 範囲全体を覆う初期の円を作る
    /// 半径700m以下なら1円、それより大きければ中心1円＋周囲6円（半径はそれぞれ元の半分）
    static func initialTiles(center: GeoPoint, radiusMeters: Double) -> [Tile] {
        guard radiusMeters > 700 else {
            return [Tile(center: center, radius: radiusMeters)]
        }
        let r = radiusMeters * 0.5
        let d = radiusMeters * 0.866
        var tiles = [Tile(center: center, radius: r)]
        for i in 0..<6 {
            let angle = Double(i) * .pi / 3
            tiles.append(Tile(
                center: center.offset(northMeters: d * cos(angle), eastMeters: d * sin(angle)),
                radius: r
            ))
        }
        return tiles
    }

    /// 円を4分割する（各象限に、元の0.6倍の半径の円を置く）
    static func subdivide(_ tile: Tile) -> [Tile] {
        let offset = tile.radius * 0.5
        let radius = tile.radius * 0.6
        return [
            Tile(center: tile.center.offset(northMeters: offset, eastMeters: offset), radius: radius),
            Tile(center: tile.center.offset(northMeters: offset, eastMeters: -offset), radius: radius),
            Tile(center: tile.center.offset(northMeters: -offset, eastMeters: offset), radius: radius),
            Tile(center: tile.center.offset(northMeters: -offset, eastMeters: -offset), radius: radius)
        ]
    }

    func collect(
        center: GeoPoint,
        radiusMeters: Double,
        types: [String],
        maxCalls: Int
    ) async -> Result {
        var queue = Self.initialTiles(center: center, radiusMeters: radiusMeters)
        var seen: [String: Place] = [:]
        var order: [String] = []
        var calls = 0
        var saturated = 0
        var firstError: Error? = nil

        while !queue.isEmpty && calls < maxCalls {
            let tile = queue.removeFirst()
            calls += 1
            let found: [Place]
            do {
                found = try await client.searchNearby(
                    center: tile.center,
                    radiusMeters: tile.radius,
                    types: types,
                    rankByDistance: true,
                    maxResults: Self.pageLimit
                )
            } catch {
                // 最初の呼び出しが失敗したら設定ミスの可能性が高いので呼び出しを止める
                if calls == 1 {
                    return Result(places: [], apiCalls: calls, saturatedTiles: 0, error: error)
                }
                firstError = firstError ?? error
                continue
            }

            for place in found where seen[place.id] == nil {
                seen[place.id] = place
                order.append(place.id)
            }

            if found.count >= Self.pageLimit {
                saturated += 1
                // 残りの予算で分割分を呼べる場合だけ分割する
                if tile.radius > Self.minTileRadius && calls + queue.count < maxCalls {
                    queue.append(contentsOf: Self.subdivide(tile))
                }
            }
        }

        // 分割した円は範囲の外にはみ出すため、指定範囲内の候補だけ残す
        let limit = radiusMeters * 1.05
        let places = order.compactMap { seen[$0] }.filter { place in
            GeoPoint(latitude: place.latitude, longitude: place.longitude).distance(to: center) <= limit
        }
        return Result(places: places, apiCalls: calls, saturatedTiles: saturated, error: firstError)
    }
}
