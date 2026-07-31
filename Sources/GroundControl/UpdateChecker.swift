import Foundation

struct UpdateInfo: Sendable {
    let version: String      // e.g. "v0.3.0"
    let url: URL             // release page (fallback)
    let downloadURL: URL     // direct zip download
}

enum UpdateChecker {
    /// Checks the latest GitHub release. Returns non-nil only when a newer version exists.
    static func check() async -> UpdateInfo? {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard let apiURL = URL(string: "https://api.github.com/repos/050177/ground-control/releases/latest") else { return nil }

        var req = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("GroundControl/\(current)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let htmlUrl = json["html_url"] as? String,
              let releaseURL = URL(string: htmlUrl) else { return nil }

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(latest, than: current) else { return nil }

        // Prefer the first attached zip asset; fall back to constructing the URL from the tag.
        let downloadURL: URL
        if let assets = json["assets"] as? [[String: Any]],
           let first = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
           let rawURL = first["browser_download_url"] as? String,
           let assetURL = URL(string: rawURL) {
            downloadURL = assetURL
        } else {
            let encoded = "Ground%20Control.zip"
            downloadURL = URL(string: "https://github.com/050177/ground-control/releases/download/\(tag)/\(encoded)")!
        }
        return UpdateInfo(version: tag, url: releaseURL, downloadURL: downloadURL)
    }

    private static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(av.count, bv.count) {
            let ai = i < av.count ? av[i] : 0
            let bi = i < bv.count ? bv[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
}
