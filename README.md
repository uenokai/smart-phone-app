# LocalRecommend - 地域のお気に入り発見アプリ

GoogleマップやTabelogなどのデータを活用し、地域の飲食店と観光スポットを**複数の条件と個人の好みに基づいてレコメンド**するiOSアプリです。

**このアプリの価値は、メジャーなお店やスポット以外を知れることにあります。**
「評価は高いのに口コミが少ない＝まだ知られていない良いお店」を独自の穴場スコアで発掘し、💎バッジと紫ピンで提示します。

## 機能概要

### コアUI
- **ホーム画面**：Googleマップを表示し、検索結果をピンで表示
- **条件指定パネル**：複数の条件を組み合わせて検索
- **詳細表示**：ピンをタップして店舗情報を確認

### 主な機能
- ✅ カテゴリ選択（飲食店 / 観光スポット）
- ✅ 価格帯・距離・ジャンル・営業状況による絞り込み
- ✅ Google口コミ・食べログ評価の表示
- ✅ 条件プリセットの保存・読み込み
- ✅ Google Mapsへのリンク
- ✅ 会員機能（Sign in with Apple）
- ✅ お気に入り登録（会員限定）
- ✅ 好みプロファイル（雰囲気タグ・穴場重視度・チェーン店除外）
- ✅ 穴場スコアリング（💎バッジ・紫ピンで穴場を可視化）

### 好みプロファイルと穴場発見について
検索パネルの「好みの設定」から、自分の好みを細かく伝えられます：

- **穴場重視度スライダー**：「評価の高さ重視」〜「穴場重視」を調整。穴場側に寄せるほど、評価は高いのに口コミが少ない場所が上位に表示されます
- **チェーン店除外**：全国チェーンを検索結果から除外（デフォルトON）
- **口コミ数の上限**：「〜100件」などを設定すると、口コミの多い有名店・観光名所が除外されます
- **好みの雰囲気タグ**：「隠れ家」「静か」「老舗」「個人経営」など。店名・口コミにタグが含まれる場所を優先します
- **避けたいものタグ**：「行列」「混雑」「観光客」など。該当する場所は順位が下がります
- **好みの自動学習**：お気に入りに登録した場所に共通する雰囲気タグ（2件以上で共通するもの）を自動で学習し、検索時に加点します。学習したタグは「好みの設定」画面の「あなたの傾向」で確認できます

### 口コミ取得の仕組み（2段階検索）
Nearby Searchは口コミ本文を返さないため、検索は2段階で行います：

1. Nearby Searchで候補を取得し、評価・口コミ数で一次ランキング
2. 上位15件にPlace Details APIで口コミ本文・営業時間・連絡先を追加取得（日本語指定・fields絞り込みでAPI課金を抑制）
3. 口コミテキストを使って好みタグ・学習タグとのマッチングで最終ランキング

これにより、詳細画面の営業時間・電話番号・口コミも検索直後から表示されます。

穴場と判定された場所は、検索結果カードと詳細画面に **💎 穴場** バッジが付き、マップ上では**紫のピン**で表示されます。

### 会員機能について
- **未登録でも利用可能**：検索・マップ表示・詳細閲覧は会員登録なしで使えます
- **お気に入りは会員限定**：お店やスポットのお気に入り登録にはサインイン（無料）が必要です
- 認証には **Sign in with Apple** を採用（メールアドレス・パスワード不要）
- お気に入りは会員IDごとに端末内に保存されます

## セットアップ手順

### 1. Xcodeプロジェクトを生成する

このリポジトリは [XcodeGen](https://github.com/yonaskolb/XcodeGen) でプロジェクトファイルを生成します（`.xcodeproj`はコミットしません）。

```bash
git clone <repository-url>
cd smart-phone-app
brew install xcodegen   # 未インストールの場合
xcodegen generate
open LocalRecommend.xcodeproj
```

アプリ本体（LocalRecommend）とユニットテスト（LocalRecommendTests）のターゲット・スキームが自動生成されます。

### 2. Google Places APIキーを取得

1. [Google Cloud Console](https://console.cloud.google.com) にアクセス
2. 新しいプロジェクトを作成
3. Places API と Maps SDK for iOS を有効化
4. APIキーを生成
5. iOS Key制限を設定（Bundle IDを指定）

### 3. APIキーを設定

**方法1：Info.plist経由（推奨）**
- `Info.plist` ファイルを開く
- `GOOGLE_PLACES_API_KEY` の値を取得したAPIキーに変更

**方法2：環境変数経由**
- `GooglePlacesService.swift` の `init` メソッドを修正

### 4. Xcodeでビルド & 実行

1. ターゲットを `LocalRecommend` に設定
2. デバイスを選択（シミュレーターまたは実機）
3. `Cmd + R` でビルド & 実行

### 5. 位置情報許可

アプリを起動後、位置情報へのアクセスを許可してください。

### 6. ユニットテストの実行

Xcodeで `Cmd + U`、またはコマンドラインから：

```bash
xcodebuild test -scheme LocalRecommend -destination 'platform=iOS Simulator,name=iPhone 15'
```

テスト対象：
- `RecommendationEngineTests`：穴場スコア・チェーン判定・ランキング・タグ加点
- `SearchFilterTests`：価格帯・最低評価・営業中フィルターの判定
- `FavoritesLearningTests`：お気に入りからの好み自動学習

## ファイル構成

```
smart-phone-app/
├── Models/
│   ├── Place.swift              # お店/スポット・検索条件モデル
│   ├── TasteProfile.swift       # 好みプロファイルモデル
│   └── User.swift               # 会員モデル
├── ViewModels/
│   ├── MapViewModel.swift       # マップロジック
│   ├── SearchViewModel.swift    # 検索条件ロジック
│   ├── TasteProfileViewModel.swift # 好みプロファイル管理
│   ├── AuthViewModel.swift      # 会員認証（Sign in with Apple）
│   └── FavoritesViewModel.swift # お気に入り管理（会員限定）
├── Views/
│   ├── ContentView.swift        # メイン画面
│   ├── MapView.swift            # マップ表示（穴場は紫ピン）
│   ├── FilterPanelView.swift    # 条件指定パネル
│   ├── TasteProfileView.swift   # 好みの設定画面
│   ├── DetailView.swift         # 詳細表示（お気に入りボタン付き）
│   ├── LoginView.swift          # 会員登録・サインイン画面
│   ├── AccountView.swift        # アカウント画面
│   └── FavoritesListView.swift  # お気に入り一覧
├── Services/
│   ├── GooglePlacesService.swift # Google Places API統合
│   └── RecommendationEngine.swift # 穴場スコアリング・好みマッチング
├── Tests/
│   ├── RecommendationEngineTests.swift # エンジンのユニットテスト
│   ├── SearchFilterTests.swift  # フィルター判定のテスト
│   └── FavoritesLearningTests.swift # 好み自動学習のテスト
├── project.yml                  # XcodeGen 設定（.xcodeproj生成用）
├── LocalRecommendApp.swift      # アプリエントリーポイント
├── LocalRecommend.entitlements  # Sign in with Apple 用エンタイトルメント
├── Info.plist                   # プロジェクト設定
└── README.md                    # このファイル
```

### Sign in with Apple のセットアップ

会員機能を動かすには、Xcode側で以下の設定が必要です：

1. Xcodeでターゲットの **Signing & Capabilities** を開く
2. **+ Capability** から **Sign in with Apple** を追加
3. `LocalRecommend.entitlements` がターゲットに紐付いていることを確認
4. Apple Developer Program のチームで署名（実機テスト時）

※ シミュレーターでもApple IDでサインインしていればテスト可能です。

## 開発進捗

### Phase 1: 基本構造 ✅
- [x] Xcode プロジェクト初期化
- [x] MapKit でマップ表示
- [x] Google Places API統合基盤
- [x] 複数条件フィルタリング
- [x] マップ上にピン表示

### Phase 2: UX改善 🔄 (進行中)
- [x] 会員機能（Sign in with Apple）
- [x] お気に入り登録・一覧（会員限定）
- [x] 好みプロファイル（雰囲気タグ・穴場重視度）
- [x] 穴場スコアリングとバッジ表示
- [x] お気に入りからの好み自動学習
- [x] Details APIによる口コミ本文の取得（2段階検索）
- [x] 価格帯・最低評価・営業中フィルターの適用（API+クライアント側）
- [x] XcodeGenによるプロジェクト生成対応
- [x] ユニットテスト（エンジン・フィルター・学習ロジック）
- [ ] UIの洗練
- [ ] パフォーマンス最適化

### Phase 3: 観光スポット対応 📋
- [ ] 観光スポット用フィルタリング
- [ ] スポット詳細情報取得
- [ ] 実デバイスでの動作検証

## 技術スタック

- **言語**：Swift 5.9+
- **UI フレームワーク**：SwiftUI
- **マップ**：MapKit
- **外部API**：Google Places API
- **ストレージ**：CoreData (将来実装)
- **最小iOS**：iOS 15.0+

## トラブルシューティング

### APIキーエラー
- Google Cloud Console でAPIキーが有効か確認
- Bundle IDが正しいか確認
- Info.plist の `GOOGLE_PLACES_API_KEY` が正しく設定されているか確認

### 位置情報が取得できない
- シミュレーターの位置情報設定を確認
- `Info.plist` の `NSLocationWhenInUseUsageDescription` が設定されているか確認
- 実機の場合、設定アプリで位置情報許可を確認

### マップが表示されない
- MapKit フレームワークが正しくリンクされているか確認
- iOS 15.0以上のターゲットを使用しているか確認

## 将来の拡張予定

- ユーザーレビュー・コメント投稿機能
- ソーシャル機能（友人と条件をシェア）
- 食べログAPI統合
- AR機能（方向表示）
- オフラインマップ

## ライセンス

MIT License

## 開発者

Claude - LocalRecommend Development Team
