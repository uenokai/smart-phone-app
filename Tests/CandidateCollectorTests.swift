import XCTest
@testable import LocalRecommend

/// 範囲を円に分けて距離順に候補を集める処理の確認（通信は行わず、モックで応答する）
final class CandidateCollectorTests: XCTestCase {

    /// 呼び出された円の中心から一定数の店を返すモック
    final class MockPlacesClient: PlacesSearching, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var calls: [(center: GeoPoint, radius: Double)] = []
        /// 円の中心ごとに返す件数を決める
        var countForTile: (GeoPoint, Double) -> Int = { _, _ in 5 }
        var failOnCall: Int? = nil

        func searchNearby(center: GeoPoint, radiusMeters: Double, types: [String], rankByDistance: Bool, maxResults: Int) async throws -> [Place] {
            lock.lock()
            calls.append((center, radiusMeters))
            let callIndex = calls.count
            lock.unlock()
            if failOnCall == callIndex {
                throw PlacesAPIError.apiError(status: "PERMISSION_DENIED", message: "test")
            }
            XCTAssertTrue(rankByDistance, "候補集めは必ず距離順で取る")
            let count = min(countForTile(center, radiusMeters), maxResults)
            return (0..<count).map { i in
                // 円の中心付近に等間隔で置く（IDは座標から作るので隣接する円で重複する）
                let point = center.offset(northMeters: Double(i) * 10, eastMeters: 0)
                let id = String(format: "%.5f_%.5f", point.latitude, point.longitude)
                return Place(
                    id: id, name: "店\(id)", category: .restaurant,
                    latitude: point.latitude, longitude: point.longitude, address: "東京都",
                    priceLevel: nil, rating: 4.0, userRatingsTotal: 10, openingHours: nil,
                    website: nil, phoneNumber: nil, reviews: nil
                )
            }
        }

        func fetchDetails(placeId: String) async throws -> Place {
            throw PlacesAPIError.invalidURL
        }
    }

    private let tokyo = GeoPoint(latitude: 35.6595, longitude: 139.7005)

    func testInitialTiles_小さい範囲は1円_大きい範囲は7円() {
        XCTAssertEqual(CandidateCollector.initialTiles(center: tokyo, radiusMeters: 500).count, 1)
        let tiles = CandidateCollector.initialTiles(center: tokyo, radiusMeters: 2000)
        XCTAssertEqual(tiles.count, 7)
        XCTAssertEqual(tiles[0].center, tokyo)
        for tile in tiles {
            XCTAssertEqual(tile.radius, 1000, accuracy: 0.001)
            XCTAssertLessThanOrEqual(tile.center.distance(to: tokyo), 2000 * 0.866 + 1)
        }
    }

    func testSubdivide_4つの小さい円になる() {
        let tile = CandidateCollector.Tile(center: tokyo, radius: 1000)
        let parts = CandidateCollector.subdivide(tile)
        XCTAssertEqual(parts.count, 4)
        for part in parts {
            XCTAssertEqual(part.radius, 600, accuracy: 0.001)
            XCTAssertEqual(part.center.distance(to: tokyo), 500 * sqrt(2), accuracy: 5)
        }
    }

    func testCollect_重複を除いて集め呼び出し回数を守る() async {
        let client = MockPlacesClient()
        client.countForTile = { _, _ in 5 }
        let collector = CandidateCollector(client: client)

        let result = await collector.collect(center: tokyo, radiusMeters: 2000, types: ["restaurant"], maxCalls: 8)

        XCTAssertEqual(result.apiCalls, 7, "7円で足りれば8回目は呼ばない")
        XCTAssertEqual(result.saturatedTiles, 0)
        XCTAssertNil(result.error)
        XCTAssertEqual(Set(result.places.map { $0.id }).count, result.places.count, "IDの重複がない")
        XCTAssertEqual(result.places.count, 35)
    }

    func testCollect_20件で打ち切られた円は予算の範囲で分割する() async {
        let client = MockPlacesClient()
        client.countForTile = { _, _ in 20 }
        let collector = CandidateCollector(client: client)

        let result = await collector.collect(center: tokyo, radiusMeters: 500, types: ["restaurant"], maxCalls: 4)

        XCTAssertEqual(result.apiCalls, 4, "最初の1円が飽和したので残り予算で分割した円を3つ呼ぶ")
        XCTAssertGreaterThan(result.saturatedTiles, 0)
        XCTAssertGreaterThan(result.places.count, 20, "分割した円から追加の候補が集まる")
    }

    func testCollect_予算が1回なら分割しない() async {
        let client = MockPlacesClient()
        client.countForTile = { _, _ in 20 }
        let collector = CandidateCollector(client: client)

        let result = await collector.collect(center: tokyo, radiusMeters: 500, types: ["restaurant"], maxCalls: 1)

        XCTAssertEqual(result.apiCalls, 1)
        XCTAssertEqual(result.places.count, 20)
    }

    func testCollect_範囲の外の候補は捨てる() async {
        let client = MockPlacesClient()
        // 中心の円だけ、範囲の外（北に3km）まで並ぶ店を返す
        client.countForTile = { center, _ in center == self.tokyo ? 20 : 0 }
        let collector = CandidateCollector(client: client)

        let result = await collector.collect(center: tokyo, radiusMeters: 150, types: ["restaurant"], maxCalls: 1)

        // 10m 間隔で20件 → 0〜190m。範囲 150m × 1.05 = 157.5m までを残す
        XCTAssertEqual(result.places.count, 16)
    }

    func testCollect_最初の呼び出しが失敗したらエラーを返して止まる() async {
        let client = MockPlacesClient()
        client.failOnCall = 1
        let collector = CandidateCollector(client: client)

        let result = await collector.collect(center: tokyo, radiusMeters: 2000, types: ["restaurant"], maxCalls: 8)

        XCTAssertEqual(result.apiCalls, 1)
        XCTAssertTrue(result.places.isEmpty)
        XCTAssertNotNil(result.error)
    }

    func testCollect_途中の失敗は飛ばして続ける() async {
        let client = MockPlacesClient()
        client.failOnCall = 3
        client.countForTile = { _, _ in 5 }
        let collector = CandidateCollector(client: client)

        let result = await collector.collect(center: tokyo, radiusMeters: 2000, types: ["restaurant"], maxCalls: 8)

        XCTAssertEqual(result.apiCalls, 7)
        XCTAssertEqual(result.places.count, 30, "失敗した1円分（5件）だけ減る")
        XCTAssertNotNil(result.error, "途中の失敗も記録はする")
    }

    func testGeoPoint_距離とオフセットが整合する() {
        let moved = tokyo.offset(northMeters: 300, eastMeters: 400)
        XCTAssertEqual(tokyo.distance(to: moved), 500, accuracy: 2)
    }
}
