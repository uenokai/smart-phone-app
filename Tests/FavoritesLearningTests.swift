import XCTest
@testable import LocalRecommend

@MainActor
final class FavoritesLearningTests: XCTestCase {

    /// テストごとに一意な会員IDを使い、UserDefaultsの状態が他のテストと混ざらないようにする
    private func makeViewModel() -> FavoritesViewModel {
        let viewModel = FavoritesViewModel()
        viewModel.setUser("test_\(UUID().uuidString)")
        return viewModel
    }

    func testLearnedMoodTags_お気に入りが1件では学習しない() {
        let viewModel = makeViewModel()
        viewModel.toggleFavorite(makePlace(reviews: ["隠れ家的なお店"]))

        XCTAssertTrue(viewModel.learnedMoodTags.isEmpty)
    }

    func testLearnedMoodTags_2件に共通するタグを学習する() {
        let viewModel = makeViewModel()
        viewModel.toggleFavorite(makePlace(name: "店A", reviews: ["隠れ家的なお店です"]))
        viewModel.toggleFavorite(makePlace(name: "店B", reviews: ["まさに隠れ家という感じ"]))

        XCTAssertEqual(viewModel.learnedMoodTags, ["隠れ家"])
    }

    func testLearnedMoodTags_1件にしか現れないタグは学習しない() {
        let viewModel = makeViewModel()
        viewModel.toggleFavorite(makePlace(name: "店A", reviews: ["隠れ家的なお店です"]))
        viewModel.toggleFavorite(makePlace(name: "店B", reviews: ["静かなお店です"]))

        XCTAssertTrue(viewModel.learnedMoodTags.isEmpty)
    }

    func testLearnedMoodTags_店名からもタグを学習する() {
        let viewModel = makeViewModel()
        viewModel.toggleFavorite(makePlace(name: "隠れ家ダイニング 灯"))
        viewModel.toggleFavorite(makePlace(name: "店B", reviews: ["隠れ家のような雰囲気"]))

        XCTAssertEqual(viewModel.learnedMoodTags, ["隠れ家"])
    }

    func testToggleFavorite_解除すると学習対象からも外れる() {
        let viewModel = makeViewModel()
        let placeA = makePlace(name: "店A", reviews: ["隠れ家的なお店です"])
        viewModel.toggleFavorite(placeA)
        viewModel.toggleFavorite(makePlace(name: "店B", reviews: ["まさに隠れ家という感じ"]))
        XCTAssertFalse(viewModel.learnedMoodTags.isEmpty)

        viewModel.toggleFavorite(placeA) // 解除

        XCTAssertTrue(viewModel.learnedMoodTags.isEmpty)
    }
}
