import SwiftUI
import AppKit

public struct HistoryView: View {
    @ObservedObject var appState = AppState.shared
    @State private var searchText = ""

    public init() {}

    private var filteredHistory: [DictationItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return appState.history
        } else {
            return appState.history.filter {
                $0.cleanedText.localizedCaseInsensitiveContains(searchText) ||
                $0.rawText.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictation History")
                        .font(.headline)
                    if appState.historyRetention == .off {
                        Text("Incognito mode active: transcriptions are not retained.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(appState.history.count) items recorded (\(appState.historyRetention.rawValue))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !appState.history.isEmpty {
                    Button(role: .destructive) {
                        appState.clearHistory()
                    } label: {
                        Label("Purge All", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Search Bar
            if !appState.history.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search dictations...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()
            }

            // List of items or Empty State
            if appState.history.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: appState.historyRetention == .off ? "shield.fill" : "text.bubble")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(appState.historyRetention == .off ? "Incognito Mode is Enabled" : "No Dictations Yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(appState.historyRetention == .off ?
                         "Your audio and text are ephemeral and immediately purged after insertion." :
                         "Hold down your Fn key and speak to start dictating.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredHistory) { item in
                            DictationRow(item: item)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 480, height: 440)
    }
}

struct DictationRow: View {
    let item: DictationItem
    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(item.wordCount) words · \(String(format: "%.1f", item.durationSeconds))s")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.cleanedText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(copied ? .green : .secondary)
            }

            Text(item.cleanedText)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
    }
}
