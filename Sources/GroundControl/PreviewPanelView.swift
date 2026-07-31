import SwiftUI
import WebKit

// MARK: - File watcher (auto-reload on disk changes for file:// URLs)

final class FileWatcher: ObservableObject {
    private var source: DispatchSourceFileSystemObject?
    private var pendingWork: DispatchWorkItem?
    private var onReload: (() -> Void)?

    /// Watch the directory containing `urlString` and call `onReload` (debounced 500ms)
    /// when files change. No-op for non-file:// URLs.
    func watch(urlString: String, onReload: @escaping () -> Void) {
        stop()
        self.onReload = onReload
        guard let url = URL(string: urlString), url.isFileURL else { return }

        let dir = url.deletingLastPathComponent().path
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .attrib], queue: .main
        )
        src.setEventHandler { [weak self] in self?.scheduleReload() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
        pendingWork?.cancel()
        pendingWork = nil
    }

    private func scheduleReload() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onReload?() }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    deinit { stop() }
}

// MARK: - WKWebView representable

struct WebViewRepresentable: NSViewRepresentable {
    let urlString: String
    let reloadToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        guard urlString != coord.lastURL || reloadToken != coord.lastToken else { return }
        coord.lastURL = urlString
        coord.lastToken = reloadToken
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }
        if url.isFileURL {
            // Grant read access to the whole directory so relative CSS/JS paths resolve.
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastURL = ""
        var lastToken = -1

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!,
                     withError _: Error) {
            // Server may not be up yet — fail silently; user can refresh manually.
        }
    }
}

// MARK: - Preview panel

struct PreviewPanelView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var watcher = FileWatcher()
    @State private var reloadToken = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                Theme.bg
                if appState.previewURL.isEmpty {
                    emptyState
                } else {
                    WebViewRepresentable(urlString: appState.previewURL, reloadToken: reloadToken)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
        }
        .onAppear {
            watcher.watch(urlString: appState.previewURL) { reloadToken += 1 }
        }
        .onChange(of: appState.previewURL) { _, url in
            watcher.watch(urlString: url) { reloadToken += 1 }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("PREVIEW")
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(Theme.dim)
            TextField("http://localhost:3000", text: $appState.previewURL)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.landed)
                .textFieldStyle(.plain)
                .onSubmit { reloadToken += 1 }
            Button(action: { reloadToken += 1 }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(TitleBarButtonStyle())
            .help("Reload preview")
            Button(action: { appState.previewVisible = false }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(TitleBarButtonStyle())
            .help("Close preview")
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.dim)
            Text("Enter a URL above")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
            Text("or an agent can call preview_url")
                .font(Theme.mono(9))
                .foregroundStyle(Theme.dim.opacity(0.6))
        }
    }
}
