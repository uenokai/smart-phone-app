import SwiftUI

/// 好みプロファイル設定画面
/// 「メジャーな場所以外を知りたい」度合いや好みの雰囲気を細かく伝えられる
struct TasteProfileView: View {
    @ObservedObject var tasteProfileViewModel: TasteProfileViewModel
    /// お気に入りの傾向から自動学習したタグ（表示のみ・検索時に自動で考慮される）
    var learnedTags: [String] = []
    /// Brave Search API キーが設定されているか（未設定ならネット口コミは使えない）
    var isWebMentionAvailable: Bool = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                // 穴場重視度
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("評価の高さ重視")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("穴場重視")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                        Slider(
                            value: $tasteProfileViewModel.profile.hiddenGemWeight,
                            in: 0.0...1.0,
                            step: 0.1
                        )
                        Text(hiddenGemWeightDescription)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("穴場度", systemImage: "sparkles")
                } footer: {
                    Text("「穴場重視」に寄せるほど、評価は高いのに候補の中で口コミが少ない＝まだ知られていない店が上位に表示されます。評価は口コミ数で補正するため、口コミ数件の5.0が最上位に来ることはありません。")
                }

                // 情報源
                Section {
                    Toggle("ネット上の口コミも参考にする", isOn: $tasteProfileViewModel.profile.useWebMentions)
                        .disabled(!isWebMentionAvailable)
                    Toggle("行った・知ってた・お気に入りの店を外す", isOn: $tasteProfileViewModel.profile.hideKnownPlaces)
                } header: {
                    Label("情報源と除外", systemImage: "network")
                } footer: {
                    if isWebMentionAvailable {
                        Text("ブログ・SNSの投稿を「本物の口コミ」として加点します。プレスリリース・PR・タイアップ・提供・案件・モニター・招待の表記があるページは評価に使いません。テレビ・ニュースでの露出は「すでに知られている」根拠として扱います。")
                    } else {
                        Text("ネット上の口コミを使うには Info.plist に BRAVE_SEARCH_API_KEY を設定してください（README参照）。")
                    }
                }

                // メジャーな場所の除外
                Section {
                    Toggle("チェーン店を除外", isOn: $tasteProfileViewModel.profile.excludeChains)

                    Picker("口コミ数の上限", selection: $tasteProfileViewModel.profile.maxReviewCount) {
                        Text("こだわらない").tag(Int?.none)
                        ForEach(TasteProfile.maxReviewCountOptions.compactMap { $0 }, id: \.self) { count in
                            Text("〜\(count)件").tag(Int?.some(count))
                        }
                    }
                } header: {
                    Label("メジャーな場所の除外", systemImage: "person.3.slash")
                } footer: {
                    Text("チェーン店は、店名のキーワードに加えて「候補の中に同名の支店が複数ある」ことでも判定します。口コミ数の上限を設定すると、それ以上口コミがある「有名な場所」が検索結果から除外されます。")
                }

                // 好みの雰囲気タグ
                Section {
                    TagGridView(
                        tags: TasteProfile.moodTagOptions,
                        selectedTags: tasteProfileViewModel.profile.moodTags,
                        selectedColor: .purple
                    ) { tag in
                        tasteProfileViewModel.toggleMoodTag(tag)
                    }
                } header: {
                    Label("好みの雰囲気", systemImage: "heart.text.square")
                } footer: {
                    Text("選んだタグが店名や口コミに含まれるお店を優先します。")
                }

                // 避けたいタグ
                Section {
                    TagGridView(
                        tags: TasteProfile.avoidTagOptions,
                        selectedTags: tasteProfileViewModel.profile.avoidTags,
                        selectedColor: .red
                    ) { tag in
                        tasteProfileViewModel.toggleAvoidTag(tag)
                    }
                } header: {
                    Label("避けたいもの", systemImage: "hand.raised")
                }

                // お気に入りから自動学習した傾向
                if !learnedTags.isEmpty {
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                            ForEach(learnedTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.purple.opacity(0.08))
                                    .foregroundColor(.purple)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.purple.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    )
                                    .cornerRadius(16)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Label("あなたの傾向（自動学習）", systemImage: "wand.and.stars")
                    } footer: {
                        Text("お気に入りに登録した場所に共通する雰囲気から自動で学習したタグです。検索時に自動的に考慮されます。")
                    }
                }
            }
            .navigationTitle("好みの設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    private var hiddenGemWeightDescription: String {
        let weight = tasteProfileViewModel.profile.hiddenGemWeight
        switch weight {
        case 0.0..<0.3: return "定番の人気店を中心に表示します"
        case 0.3..<0.7: return "人気店と穴場をバランスよく表示します"
        default: return "まだ知られていない穴場を優先して表示します"
        }
    }
}

/// タグ選択用のチップグリッド
struct TagGridView: View {
    let tags: [String]
    let selectedTags: [String]
    let selectedColor: Color
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                let isSelected = selectedTags.contains(tag)
                Button(action: { onTap(tag) }) {
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? selectedColor : Color.gray.opacity(0.15))
                        .foregroundColor(isSelected ? .white : .primary)
                        .cornerRadius(16)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TasteProfileView(tasteProfileViewModel: TasteProfileViewModel())
}
