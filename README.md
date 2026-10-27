# LocalRecommend - 知らない良い店を知るアプリ

Google Places API (New) のデータとネット上の口コミを組み合わせ、**人気順の検索では出てこない、まだ知られていない良い店**を見つけるiOSアプリです。

**このアプリの価値は、Googleマップで普通に検索しても出てこない店を知れることにあります。**
Googleマップの検索結果は人気順の上位に偏り、口コミの少ない店は埋もれます。このアプリは範囲を小さな円に分けて距離順に全件に近く候補を集め、「評価は高いのに知られていない」「本物の口コミで裏付けがある」店を上位に出します。

## 機能概要

### コアUI
- **ホーム画面**：マップに検索結果をピン表示（💎穴場＝紫、🔍未確認＝青緑）
- **条件指定パネル**：カテゴリ・価格帯・距離・営業状況・評価・候補の集め方
- **詳細表示**：判定の内訳、ネット上の言及、Googleの口コミ、「行った／知ってた／興味なし」の記録

### 主な機能
- ✅ 円分割・距離順による候補集め（人気順の上位20件に偏らない）
- ✅ 有益スコアによる並べ替えと、理由の内訳表示
- ✅ ネット上の本物の口コミ（ブログ・SNS）の加点、PR・広告・タイアップの除外
- ✅ 食べログの点数の読み取り（検索スニペットから）
- ✅ Googleの口コミの招待・PR表記の検出（評価に不使用）
- ✅ チェーン判定（キーワード＋候補内の同名支店）
- ✅ 既知の店の記録と除外（行った／知ってた／興味なし／お気に入り）
- ✅ 好みプロファイル（雰囲気タグ・穴場重視度）と、お気に入りからの自動学習
- ✅ 会員機能（Sign in with Apple）とお気に入り

## 「有益」の判定方法

総合スコア ＝ (1−h)×品質 ＋ h×未知度 ＋ 0.25×新しさ ＋ 0.3×ネットの口コミ ＋ タグ加減点 − チェーン減点
（h ＝ 穴場重視度 0〜1、既定 0.7）

| 項目 | 計算 | ねらい |
| --- | --- | --- |
| 品質 | Google評価のベイズ平均（口コミ数が少ないほど周辺平均に寄せる）。食べログの点数が読めれば35%混ぜる | 口コミ3件の5.0が口コミ80件の4.5を上回らないようにする |
| 未知度 | その検索の候補の中での口コミ数の相対位置（7割）＋絶対数（3割）。1,000件以上は0 | 都心と地方で口コミ数の水準が違うため固定のしきい値を使わない |
| 新しさ | 取得できた口コミの最新投稿日（3か月以内=1.0、2年超=0.15） | 閉店寸前・放置状態の店を下げる |
| ネットの口コミ | ブログ・SNS・投稿サイトでの言及数の対数（8件で満点） | Googleに口コミが少なくても、本物の推薦があれば拾う |
| メディア掲載 | テレビ・ニュース・グルメ記事に出ていれば未知度を0.6倍 | すでに知られている店を下げる |
| 口コミの信頼性 | 招待・PR・提供・身内と読める口コミがあれば品質を減点し、タグ照合からも除外 | 本物の口コミだけを使う |
| チェーン | キーワード表、または候補内に同名（支店名を除く）の店が複数 | 穴場志向と相反するため減点・除外 |
| 裏付けの少なさ | 口コミ5件未満かつネット言及なし → 総合×0.8、🔍未確認バッジ | 評価が高くても根拠が薄い店を区別する |

### ネット上の言及の分類（PR・広告の除外）
| 分類 | 扱い | 判定 |
| --- | --- | --- |
| 本物の口コミ | 加点 | ameblo・はてな・note・X・Instagram・Threads・TikTok・YouTube などの投稿、URLに blog/diary を含むページ |
| PR・広告 | 評価に使わない | PR TIMES 等のプレスリリース配信サイト、タイトル・本文に「PR」「タイアップ」「提供」「案件」「モニター募集」「招待」などの表記 |
| メディア | 未知度を下げる | NHK・民放・新聞・Yahoo!ニュース・ウォーカープラス・グルメ系キュレーション |
| 掲載サイト | 件数のみ表示 | 食べログ・Retty・ホットペッパー・ぐるなび・Googleマップ等（食べログは点数を読み取る） |
| 公式 | 使わない | 店の公式サイト |

判定の内訳は詳細画面の「判定の内訳」「ネット上の言及」で確認できます。

### 候補の集め方（2段階＋ネット検索）
1. 検索範囲を中心1円＋周囲6円に分け、各円を **距離順** で取得（Nearby Search、1回20件）。20件で打ち切られた円は、呼び出し回数の余裕がある限り4分割して取り直す
2. 価格帯・最低評価・営業中・営業状態で絞り込み、一次採点
3. 上位15件に Place Details で口コミ本文・投稿日・営業時間・連絡先を付加
4. 上位10件の店名＋市区町村で Brave Search を実行し、言及を分類・集計（14日間キャッシュ）
5. 候補全体の統計で最終採点し、上位30件を表示

「候補の集め方」は 速い（4回）／標準（8回）／徹底（16回）から選べます。

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

### 2. Google Places API (New) のキーを取得

旧 Places API は 2026年10月以降、新規の Google Cloud プロジェクトでは有効化できません。**Places API (New)** を使います。

1. [Google Cloud Console](https://console.cloud.google.com) でプロジェクトを作成
2. 「Places API (New)」を有効化
3. APIキーを作成し、**アプリケーションの制限：iOSアプリ**（Bundle ID `com.localrecommend.app`）、**APIの制限：Places API (New)** を設定
4. `Info.plist` の `GOOGLE_PLACES_API_KEY` に設定

#### 料金の目安（2026年10月時点の公開価格）
| 呼び出し | SKU | 無料枠（月） | 超過時 |
| --- | --- | --- | --- |
| Nearby Search（評価・口コミ数まで） | Enterprise | 1,000回 | $35 / 1,000回 |
| Place Details（口コミ本文まで） | Enterprise + Atmosphere | 1,000回 | $25 / 1,000回 |
| 写真 | Place Photos | 1,000回 | $7 / 1,000回 |

1回の検索で Nearby Search を4〜16回、Place Details を最大15回、写真を詳細画面を開いた分だけ使います。標準設定なら無料枠で月60回ほど検索できます。

### 3. Brave Search API のキーを取得（ネット上の口コミを使う場合）

Google Custom Search JSON API は新規受付を終了したため、Brave Search API を使います。

1. [Brave Search API](https://brave.com/search/api/) でアカウントを作成（カード登録が必要）
2. Search プランのキーを発行（$5 / 1,000件、毎月 $5 分＝約1,000件の無料枠）
3. `Info.plist` の `BRAVE_SEARCH_API_KEY` に設定

未設定でもアプリは動きます（ネットの口コミ・食べログ点数の項目が空になります）。1回の検索で最大10件の店を調べ、結果は14日間キャッシュします。

### 4. Xcodeでビルド & 実行

1. ターゲットを `LocalRecommend` に設定
2. デバイスを選択（シミュレーターまたは実機）
3. `Cmd + R` でビルド & 実行

### 5. 位置情報許可

アプリを起動後、位置情報へのアクセスを許可してください。

### 6. ユニットテストの実行

Xcodeで `Cmd + U`、またはコマンドラインから：

```bash
xcodebuild test -scheme LocalRecommend -destination 'platform=iOS Simulator,name=iPhone 16'
```

テスト対象（通信は行いません）：
- `RecommendationEngineTests`：ベイズ平均・候補内未知度・新しさ・ネット言及・食べログ・口コミの信頼性・チェーン判定・バッジ・理由
- `WebMentionAnalyzerTests`：言及の分類・PRの検出と誤検知防止・ドメイン単位の集計・食べログ点数の読み取り・住所からの市区町村抽出
- `CandidateCollectorTests`：円分割・分割の予算・重複除去・範囲外の除外・エラー処理
- `PlacesAPIDecodingTests`：Places API (New) のレスポンス変換・旧データとの互換
- `SearchFilterTests`：価格帯・最低評価・営業中・営業状態・店名・旧プリセットの互換
- `KnownPlacesTests`：既知の店の記録と除外
- `FavoritesLearningTests`：お気に入りからの好み自動学習

## ファイル構成

```
smart-phone-app/
├── Models/
│   ├── Place.swift              # お店・検索条件モデル（Places API (New) 対応）
│   ├── WebMention.swift         # ネット言及・食べログ点数モデル
│   ├── GeoPoint.swift           # 緯度経度（距離・オフセット計算）
│   ├── NameNormalizer.swift     # 支店名の除去・店名の比較
│   ├── TasteProfile.swift       # 好みプロファイルモデル
│   └── User.swift               # 会員モデル
├── ViewModels/
│   ├── MapViewModel.swift       # 検索の流れ（候補集め→詳細→ネット言及→採点）
│   ├── SearchViewModel.swift    # 検索条件・プリセット
│   ├── TasteProfileViewModel.swift # 好みプロファイル管理
│   ├── KnownPlacesViewModel.swift  # 既知の店（行った／知ってた／興味なし）
│   ├── AuthViewModel.swift      # 会員認証（Sign in with Apple）
│   └── FavoritesViewModel.swift # お気に入り管理（会員限定）
├── Views/
│   ├── ContentView.swift        # メイン画面・結果カード
│   ├── MapView.swift            # マップ表示（穴場は紫、未確認は青緑）
│   ├── FilterPanelView.swift    # 条件指定パネル
│   ├── TasteProfileView.swift   # 好みの設定画面
│   ├── DetailView.swift         # 詳細表示（判定の内訳・ネット言及・口コミ・既知の記録）
│   ├── LoginView.swift          # 会員登録・サインイン画面
│   ├── AccountView.swift        # アカウント画面・既知の店一覧
│   └── FavoritesListView.swift  # お気に入り一覧
├── Services/
│   ├── GooglePlacesService.swift   # Places API (New)：Nearby Search / Place Details / 写真
│   ├── CandidateCollector.swift    # 円分割・距離順の候補集め
│   ├── WebMentionService.swift     # Brave Search API クライアント・キャッシュ
│   ├── WebMentionAnalyzer.swift    # 言及の分類・PR検出・食べログ点数・住所解析
│   └── RecommendationEngine.swift  # 有益スコアの採点・理由の内訳
├── Tests/                       # ユニットテスト
├── project.yml                  # XcodeGen 設定（.xcodeproj生成用）
├── LocalRecommendApp.swift      # アプリエントリーポイント
├── LocalRecommend.entitlements  # Sign in with Apple 用エンタイトルメント
├── Info.plist                   # プロジェクト設定・APIキー
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

### Phase 2: UX改善 ✅
- [x] 会員機能（Sign in with Apple）
- [x] お気に入り登録・一覧（会員限定）
- [x] 好みプロファイル（雰囲気タグ・穴場重視度）
- [x] 穴場スコアリングとバッジ表示
- [x] お気に入りからの好み自動学習
- [x] Details APIによる口コミ本文の取得
- [x] 価格帯・最低評価・営業中フィルターの適用
- [x] XcodeGenによるプロジェクト生成対応
- [x] ユニットテスト
- [x] 検索パネルの開閉式化・地図中心を検索起点に・自動ズーム・ダークモード・距離表示
- [x] GitHub Actions CI

### Phase 3: 判定の再設計（知らない良い店を知る）✅
- [x] Places API (New) への移行（旧APIは新規プロジェクトで有効化不可）
- [x] 円分割・距離順の候補集め
- [x] ベイズ平均・候補内未知度・新しさによる採点と理由の内訳
- [x] ネット上の本物の口コミの加点、PR・広告・メディアの分類
- [x] 食べログ点数の読み取り（検索スニペット）
- [x] Googleの口コミの招待・PR表記の検出
- [x] 既知の店の記録と除外
- [x] 写真表示（Place Photos）

### Phase 4: 予定 📋
- [ ] Apify を使った食べログ・Instagram・X の口コミ本文の取得（利用規約・料金・所要時間の確認が前提）
- [ ] 観光スポット向けの判定調整
- [ ] 実デバイスでの動作検証

## 技術スタック

- **言語**：Swift 5.9+
- **UI フレームワーク**：SwiftUI
- **マップ**：MapKit
- **外部API**：Google Places API (New)、Brave Search API
- **ストレージ**：UserDefaults（設定・お気に入り・既知の店）、Caches（ネット言及）
- **最小iOS**：iOS 15.0+

## Macを持っていない場合

このリポジトリには GitHub Actions のCI（`.github/workflows/ci.yml`）を設定済みです。ブランチにプッシュするたびに、macOSランナー上で自動的に以下が実行されます：

1. `xcodegen generate` でXcodeプロジェクトを生成
2. `xcodebuild test` でビルド＆ユニットテストを実行

GitHubリポジトリの **Actions** タブから結果（緑✅ / 赤❌）を確認できるため、Macを持っていなくても「コードが壊れていないか」は継続的に確認できます。

ただし、実際の画面表示や操作感（UI/UX）はCIでは確認できません。シミュレーターを操作して見た目を確認したい場合は、[MacinCloud](https://www.macincloud.com/) や [MacStadium](https://www.macstadium.com/) などのクラウドMacサービスの利用を検討してください。

## トラブルシューティング

### APIキーエラー（Google Places API エラー（PERMISSION_DENIED）…）
- 「Places API (New)」が有効か確認（旧「Places API」とは別）
- APIキーの制限が iOS アプリ＋Bundle ID `com.localrecommend.app` になっているか確認
- `Info.plist` の `GOOGLE_PLACES_API_KEY` が正しく設定されているか確認

### ネット上の言及が「未設定」と表示される
- `Info.plist` の `BRAVE_SEARCH_API_KEY` を設定し、アプリを再起動してください
- 「好みの設定」の「ネット上の口コミも参考にする」がONか確認

### 位置情報が取得できない
- シミュレーターの位置情報設定を確認
- `Info.plist` の `NSLocationWhenInUseUsageDescription` が設定されているか確認
- 実機の場合、設定アプリで位置情報許可を確認

## ライセンス

MIT License

## 開発者

Claude - LocalRecommend Development Team
