import SwiftUI

struct BrowserView: View {
    @State private var model = BrowserModel()
    @State private var address = ""
    @State private var showDetected = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            progressBar
            WebView(webView: model.webView)
            toolbar
        }
        .onChange(of: model.currentURL, initial: true) { _, url in
            if !addressFocused { address = url?.absoluteString ?? "" }
        }
        .sheet(isPresented: $showDetected) {
            DetectedStreamsList(streams: model.detectedStreams)
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: addressFocused ? "magnifyingglass" : "globe")
                .foregroundStyle(.secondary)
            TextField("検索または URL を入力", text: $address)
                .focused($addressFocused)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .onSubmit {
                    model.load(address)
                    addressFocused = false
                }
            if addressFocused, !address.isEmpty {
                Button {
                    address = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    if model.isLoading { model.stopLoading() } else { model.reload() }
                } label: {
                    Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var progressBar: some View {
        ProgressView(value: model.progress, total: 1.0)
            .progressViewStyle(.linear)
            .frame(height: 2)
            .opacity(model.isLoading ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: model.isLoading)
    }

    private var toolbar: some View {
        HStack {
            Button { model.goBack() } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!model.canGoBack)

            Spacer()

            Button { model.goForward() } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!model.canGoForward)

            Spacer()

            Button { showDetected = true } label: {
                Image(systemName: "music.note.list")
                    .overlay(alignment: .topTrailing) {
                        if !model.detectedStreams.isEmpty {
                            Text("\(model.detectedStreams.count)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.red, in: Circle())
                                .offset(x: 12, y: -10)
                        }
                    }
            }
            .disabled(model.detectedStreams.isEmpty)

            Spacer()

            Button { model.load("https://m.youtube.com") } label: {
                Image(systemName: "house")
            }
        }
        .font(.title3)
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct DetectedStreamsList: View {
    let streams: [DetectedStream]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(streams) { stream in
                VStack(alignment: .leading, spacing: 4) {
                    Text(stream.name?.isEmpty == false ? stream.name! : "(無題)")
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let type = stream.mimeType, !type.isEmpty {
                            Text(type)
                        }
                        if let duration = stream.duration, duration > 0 {
                            Text(formatted(duration))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(stream.src)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .overlay {
                if streams.isEmpty {
                    ContentUnavailableView(
                        "検出なし",
                        systemImage: "music.note.list",
                        description: Text("動画ページで再生すると stream を検出します")
                    )
                }
            }
            .navigationTitle("検出した stream (\(streams.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func formatted(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    BrowserView()
}
