import SwiftUI

struct BrowserView: View {
    @State private var model = BrowserModel()
    @State private var address = ""
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

            Button { model.load("https://m.youtube.com") } label: {
                Image(systemName: "house")
            }
        }
        .font(.title3)
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

#Preview {
    BrowserView()
}
