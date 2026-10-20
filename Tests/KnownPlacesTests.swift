import XCTest
@testable import LocalRecommend

@MainActor
final class KnownPlacesTests: XCTestCase {

    /// テストごとに一意な保存キーを使い、UserDefaults の状態が他のテストと混ざらないようにする
    private func makeViewModel() -> KnownPlacesViewModel {
        KnownPlacesViewModel(storageKey: "known_places_test_\(UUID().uuidString)")
    }

    func testToggle_記録すると既知IDに含まれる() {
        let viewModel = makeViewModel()
        let place = makePlace(id: "a", name: "行った店")

        viewModel.toggle(place, status: .visited)

        XCTAssertEqual(viewModel.status(of: "a"), .visited)
        XCTAssertTrue(viewModel.knownIds.contains("a"))
        XCTAssertEqual(viewModel.count(of: .visited), 1)
    }

    func testToggle_同じ状態をもう一度選ぶと取り消される() {
        let viewModel = makeViewModel()
        let place = makePlace(id: "a")

        viewModel.toggle(place, status: .known)
        viewModel.toggle(place, status: .known)

        XCTAssertNil(viewModel.status(of: "a"))
        XCTAssertFalse(viewModel.knownIds.contains("a"))
    }

    func testToggle_別の状態を選ぶと上書きされる() {
        let viewModel = makeViewModel()
        let place = makePlace(id: "a")

        viewModel.toggle(place, status: .known)
        viewModel.toggle(place, status: .notInterested)

        XCTAssertEqual(viewModel.status(of: "a"), .notInterested)
        XCTAssertEqual(viewModel.knownPlaces.count, 1)
    }

    func testPersist_再生成しても記録が残る() {
        let key = "known_places_test_\(UUID().uuidString)"
        let first = KnownPlacesViewModel(storageKey: key)
        first.toggle(makePlace(id: "a", name: "保存される店"), status: .visited)

        let second = KnownPlacesViewModel(storageKey: key)

        XCTAssertEqual(second.status(of: "a"), .visited)
        XCTAssertEqual(second.knownPlaces.first?.name, "保存される店")
    }

    func testEvaluate_既知の店は検索結果から外れる() {
        let viewModel = makeViewModel()
        let known = makePlace(id: "known", name: "知ってた店")
        let unknown = makePlace(id: "unknown", name: "知らない店")
        viewModel.toggle(known, status: .known)

        let ranked = RecommendationEngine.rank([known, unknown], profile: TasteProfile(), knownIds: viewModel.knownIds)

        XCTAssertEqual(ranked.map { $0.id }, ["unknown"])
    }
}
