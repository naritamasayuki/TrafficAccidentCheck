import SwiftUI
import UIKit

/// アプリ内からバグ・不具合・改善要望を報告するためのシートビュー。
/// 入力内容は操作ごとに自動保存され、GitHub Issue（無料・公式リポジトリ連携）やクリップボードコピー、共有シートから送信できる。
struct BugReportSheetView: View {
    let filter: AccidentFilter
    let isGoogleMapsConfigured: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var draft = BugReportDraft.loadSaved()
    @State private var isShowingCopiedBanner = false
    @State private var isShowingFirstClearAlert = false
    @State private var isShowingSecondClearAlert = false

    private var appVersionString: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
        return "\(version) (\(build))"
    }

    private var osVersionString: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    private var formattedReportText: String {
        draft.buildFormattedBody(
            appVersion: appVersionString,
            osVersion: osVersionString,
            filter: filter,
            isGoogleMapsConfigured: isGoogleMapsConfigured
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("不具合・ご要望のカテゴリ") {
                    Picker("カテゴリ", selection: $draft.category) {
                        ForEach(BugReportCategory.allCases) { item in
                            Text(item.localizedName).tag(item)
                        }
                    }
                }

                Section {
                    TextEditor(text: $draft.detailText)
                        .frame(minHeight: 110)
                        .overlay(alignment: .topLeading) {
                            if draft.detailText.isEmpty {
                                Text("例：〇〇交差点付近で音声アナウンスが鳴らない、ピンの位置がずれている等、お気づきの点をご記入ください。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }

                    Toggle("端末・設定の診断情報を自動で添付する（推奨）", isOn: $draft.includeDiagnostics)
                        .font(.subheadline)
                } header: {
                    Text("発生状況・詳細内容（自動保存されます）")
                } footer: {
                    Text("※個人を特定する情報や現在地の座標は送信されません。")
                }

                Section("送信・報告方法（無料）") {
                    if let issueURL = draft.buildGitHubIssueURL(
                        appVersion: appVersionString,
                        osVersion: osVersionString,
                        filter: filter,
                        isGoogleMapsConfigured: isGoogleMapsConfigured
                    ) {
                        Button {
                            openURL(issueURL)
                        } label: {
                            Label("開発元サポート窓口（GitHub Issue）で報告する", systemImage: "paperplane.fill")
                                .font(.subheadline.bold())
                        }
                    }

                    ShareLink(item: formattedReportText) {
                        Label("メール・メッセージ等の外部アプリで送信する", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }

                    Button {
                        UIPasteboard.general.string = formattedReportText
                        withAnimation {
                            isShowingCopiedBanner = true
                        }
                    } label: {
                        Label("報告テキストをクリップボードにコピー", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }

                    if isShowingCopiedBanner {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("報告内容をコピーしました。")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        }
                    }
                }

                Section("送信される内容のプレビュー") {
                    Text(formattedReportText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                if !draft.detailText.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            isShowingFirstClearAlert = true
                        } label: {
                            Label("入力した下書きを消去してリセット", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("バグ報告・ご要望")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onChange(of: draft) { _, newDraft in
                newDraft.save()
            }
            .alert("下書きを消去しますか？", isPresented: $isShowingFirstClearAlert) {
                Button("いいえ", role: .cancel) {}
                Button("はい", role: .destructive) {
                    isShowingSecondClearAlert = true
                }
            } message: {
                Text("入力中のバグ報告テキストが初期状態に戻ります。")
            }
            .alert("最終確認：本当に下書きをリセットしますか？", isPresented: $isShowingSecondClearAlert) {
                Button("いいえ", role: .cancel) {}
                Button("消去する", role: .destructive) {
                    draft = BugReportDraft()
                    draft.save()
                    isShowingCopiedBanner = false
                }
            } message: {
                Text("消去したテキストは元に戻せません。")
            }
        }
    }
}
