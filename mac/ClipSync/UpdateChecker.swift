import Combine
import Foundation

struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
    let body: String?
}

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var downloadURL: URL?
    @Published var releaseNotes: String = ""

    // --- GitHub API Config ---
    private let repoOwner = "WinShell-Bhanu"
    private let repoName = "Clipsync"
    private let currentVersion = "1.0.0"

    // --- Update Check Logic ---
    func checkForUpdates() {
        // Changed to /releases (list) instead of /releases/latest to support Pre-releases (Betas)
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases?per_page=1"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("OTPSync-Mac-App", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                print("Update check failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            do {
                // Decode ARRAY of releases, take the first one
                let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

                if let latestRelease = releases.first {
                    DispatchQueue.main.async {
                        self?.compareVersions(
                            latestTag: latestRelease.tag_name, release: latestRelease)
                    }
                }
            } catch {
                print("Failed to parse release data: \(error)")
                if let str = String(data: data, encoding: .utf8) {
                    print("Raw Response: \(str)")
                }
            }
        }.resume()
    }

    // --- Version Comparison ---
    private func compareVersions(latestTag: String, release: GitHubRelease) {
        let cleanLatest = latestTag.replacingOccurrences(of: "v", with: "")

        // Get actual app version or use fallback
        let appVersion =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? currentVersion
        let cleanCurrent = appVersion.replacingOccurrences(of: "v", with: "")

        if isVersionNewer(current: cleanCurrent, latest: cleanLatest) {
            print("Update available: \(latestTag)")
            self.latestVersion = latestTag
            self.downloadURL = URL(string: release.html_url)
            self.releaseNotes = release.body ?? "New update available!"
            self.updateAvailable = true
        } else {
            print("App is up to date.")
        }
    }

    private func isVersionNewer(current: String, latest: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }

        let length = max(currentParts.count, latestParts.count)

        for i in 0..<length {
            let c = i < currentParts.count ? currentParts[i] : 0
            let l = i < latestParts.count ? latestParts[i] : 0

            if l > c { return true }
            if l < c { return false }
        }
        return false
    }
}
