//
//  UpdateChecker.swift
//  TTT Collection
//
//  Created on 2026-05-22.
//

import Foundation
import SwiftUI
internal import Combine

// MARK: - Version Models

struct GitHubRelease: Codable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let published_at: String
    let prerelease: Bool
}

struct GitHubCommit: Codable {
    let sha: String
    let commit: CommitDetails
    let html_url: String
}

struct CommitDetails: Codable {
    let message: String
    let author: CommitAuthor
    let committer: CommitAuthor
}

struct CommitAuthor: Codable {
    let name: String
    let date: String
}

struct GitHubTree: Codable {
    let sha: String
    let tree: [GitHubTreeItem]
    let truncated: Bool
}

struct GitHubTreeItem: Codable {
    let path: String
    let mode: String
    let type: String
    let sha: String
    let size: Int?
    let url: String
}

struct GitHubContent: Codable {
    let name: String
    let path: String
    let sha: String
    let size: Int
    let url: String
    let html_url: String
    let download_url: String?
    let type: String
    let content: String?
    let encoding: String?
}

// MARK: - Version Parser

struct AppVersion: Comparable {
    let platform: String
    let major: Int
    let minor: Int
    let patch: Int
    
    init?(from tag: String) {
        let components = tag.split(separator: "_")
        guard components.count == 2 else { return nil }
        
        func parseVersion(_ versionStr: String) -> (platform: String, major: Int, minor: Int, patch: Int)? {
            let platformPrefix: String
            let numberStr: String
            
            if versionStr.hasPrefix("AP") {
                platformPrefix = "AP"
                numberStr = String(versionStr.dropFirst(2))
            } else if versionStr.hasPrefix("AND") {
                platformPrefix = "AND"
                numberStr = String(versionStr.dropFirst(3))
            } else {
                return nil
            }
            
            let parts = numberStr.split(separator: ".")
            if parts.count == 2 {
                guard let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
                return (platformPrefix, major, minor, 0)
            } else if parts.count == 3 {
                guard let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
                return (platformPrefix, major, minor, patch)
            }
            return nil
        }
        
        guard let apVersion = parseVersion(String(components[0])) else { return nil }
        
        self.platform = "AP"
        self.major = apVersion.major
        self.minor = apVersion.minor
        self.patch = apVersion.patch
    }
    
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        guard lhs.platform == rhs.platform else { return false }
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
    
    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        return lhs.platform == rhs.platform &&
               lhs.major == rhs.major &&
               lhs.minor == rhs.minor &&
               lhs.patch == rhs.patch
    }
    
    var stringValue: String {
        return "\(major).\(minor)" + (patch > 0 ? ".\(patch)" : "")
    }
}

// MARK: - File Hash Cache

struct FileHashCache: Codable {
    let commitSha: String
    let files: [String: String]  // path -> hash
    let lastUpdated: Date
}

// MARK: - Update Checker (iOS-compatible)

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    
    @Published var isChecking = false
    @Published var updateAvailable: UpdateInfo?
    @Published var betaUpdateAvailable: BetaUpdateInfo?
    @Published var showUpdatePrompt = false
    @Published var showBetaPrompt = false
    @Published var downloadProgress: Double = 0
    @Published var downloadStatus: String = ""
    @Published var isDownloading = false
    @Published var showCloneConfirmation = false
    
    let repoOwner = "nikos-projects"
    let repoName = "playbox"
    let userDefaultsKey = "lastUpdateCheck"
    let betaOptInKey = "betaOptIn"
    let lastBetaCheckKey = "lastBetaCheck"
    let fileHashCacheKey = "fileHashCache"
    
    private var checkTimer: Timer?
    
    // Track which files we've downloaded for comparison
    private var downloadedFileHashes: [String: String] = [:]
    
    private init() {
        startPeriodicChecks()
        loadFileHashCache()
    }
    
    deinit {
        checkTimer?.invalidate()
    }
    
    private func startPeriodicChecks() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
            if UserDefaults.standard.bool(forKey: self?.betaOptInKey ?? "") {
                self?.checkForBetaUpdates()
            }
        }
    }
    
    // MARK: - File Storage
    
    private var cacheDirectory: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = paths[0].appendingPathComponent("playbox_beta_cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }
    
    private func loadFileHashCache() {
        if let data = UserDefaults.standard.data(forKey: fileHashCacheKey),
           let cache = try? JSONDecoder().decode(FileHashCache.self, from: data) {
            downloadedFileHashes = cache.files
        }
    }
    
    private func saveFileHashCache(commitSha: String) {
        let cache = FileHashCache(
            commitSha: commitSha,
            files: downloadedFileHashes,
            lastUpdated: Date()
        )
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: fileHashCacheKey)
        }
    }
    
    // MARK: - Download and Compare Repository Files
    
    func downloadAndCompareRepository(progress: @escaping (Double, String) -> Void, completion: @escaping (Bool, Bool, Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            progress(0.05, "Fetching repository tree...")
            
            // Get the repository file tree
            let treeURL = URL(string: "https://api.github.com/repos/\(self.repoOwner)/\(self.repoName)/git/trees/main?recursive=1")!
            
            let semaphore = DispatchSemaphore(value: 0)
            var tree: GitHubTree?
            var error: Error?
            
            var request = URLRequest(url: treeURL)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            
            URLSession.shared.dataTask(with: request) { data, _, taskError in
                error = taskError
                if let data = data {
                    tree = try? JSONDecoder().decode(GitHubTree.self, from: data)
                }
                semaphore.signal()
            }.resume()
            
            semaphore.wait()
            
            guard let tree = tree, error == nil else {
                DispatchQueue.main.async {
                    completion(false, false, error)
                }
                return
            }
            
            progress(0.1, "Analyzing \(tree.tree.count) files...")
            
            // Filter for Swift files and important project files
            let relevantFiles = tree.tree.filter { item in
                let ext = (item.path as NSString).pathExtension
                return ext == "swift" || ext == "xcodeproj" || ext == "xcworkspace" || item.path.contains(".pbxproj")
            }
            
            var newHashes: [String: String] = [:]
            var changedFiles: [String] = []
            var totalProcessed = 0
            
            for file in relevantFiles {
                totalProcessed += 1
                progress(0.1 + (Double(totalProcessed) / Double(relevantFiles.count)) * 0.8,
                        "Checking: \(file.path)")
                
                // Get file content hash (just the SHA, don't download full content)
                newHashes[file.path] = file.sha
                
                // Compare with cached hash
                if let cachedHash = self.downloadedFileHashes[file.path], cachedHash != file.sha {
                    changedFiles.append(file.path)
                }
            }
            
            // Update cache
            self.downloadedFileHashes = newHashes
            self.saveFileHashCache(commitSha: tree.sha)
            
            progress(1.0, "Analysis complete")
            
            let hasChanges = !changedFiles.isEmpty
            DispatchQueue.main.async {
                completion(true, hasChanges, nil)
                if hasChanges {
                    self.betaUpdateAvailable = BetaUpdateInfo(
                        hasNewCommits: true,
                        commitCount: changedFiles.count,
                        latestCommit: nil,
                        changedFiles: changedFiles
                    )
                    self.showBetaPrompt = true
                }
            }
        }
    }
    
    // MARK: - Simple Remote Check (No Download)
    
    func checkRemoteForChanges(completion: @escaping (Bool, Int, [String]?) -> Void) {
        let treeURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/git/trees/main?recursive=1")!
        
        var request = URLRequest(url: treeURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data, error == nil,
                  let tree = try? JSONDecoder().decode(GitHubTree.self, from: data) else {
                completion(false, 0, nil)
                return
            }
            
            let relevantFiles = tree.tree.filter { item in
                let ext = (item.path as NSString).pathExtension
                return ext == "swift" || ext == "xcodeproj" || item.path.contains(".pbxproj")
            }
            
            var changedFiles: [String] = []
            for file in relevantFiles {
                if let cachedHash = self?.downloadedFileHashes[file.path], cachedHash != file.sha {
                    changedFiles.append(file.path)
                } else if self?.downloadedFileHashes[file.path] == nil {
                    // New file
                    changedFiles.append(file.path)
                }
            }
            
            completion(!changedFiles.isEmpty, changedFiles.count, changedFiles)
        }.resume()
    }
    
    // MARK: - Release Check
    
    func checkForUpdates(force: Bool = false) {
        let lastCheck = UserDefaults.standard.object(forKey: userDefaultsKey) as? Date ?? .distantPast
        if !force && Date().timeIntervalSince(lastCheck) < 3600 { return }
        
        isChecking = true
        UserDefaults.standard.set(Date(), forKey: userDefaultsKey)
        
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases"
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                guard let data = data, error == nil else { return }
                
                do {
                    let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                    let currentVersion = self?.getCurrentAppVersion()
                    
                    let latestRelease = releases.first { !$0.prerelease }
                    
                    if let release = latestRelease,
                       let releaseVersion = AppVersion(from: release.tag_name),
                       let current = currentVersion {
                        
                        if releaseVersion > current {
                            self?.updateAvailable = UpdateInfo(
                                version: releaseVersion,
                                release: release
                            )
                            self?.showUpdatePrompt = true
                        }
                    }
                } catch {
                    print("Failed to decode releases: \(error)")
                }
            }
        }.resume()
    }
    
    // MARK: - Beta Tracking
    
    func optIntoBetaTracking() {
        UserDefaults.standard.set(true, forKey: betaOptInKey)
        DispatchQueue.main.async {
            self.showCloneConfirmation = true
        }
    }
    
    func performInitialDownload() {
        isDownloading = true
        downloadAndCompareRepository { [weak self] progress, status in
            DispatchQueue.main.async {
                self?.downloadProgress = progress
                self?.downloadStatus = status
            }
        } completion: { [weak self] success, hasChanges, error in
            DispatchQueue.main.async {
                self?.isDownloading = false
                if success && hasChanges {
                    self?.checkForBetaUpdates(force: true)
                }
            }
        }
    }
    
    func optOutOfBetaTracking() {
        UserDefaults.standard.set(false, forKey: betaOptInKey)
        UserDefaults.standard.removeObject(forKey: fileHashCacheKey)
        
        // Clear cached files
        try? FileManager.default.removeItem(at: cacheDirectory)
        downloadedFileHashes.removeAll()
        
        betaUpdateAvailable = nil
    }
    
    func isOptedIntoBeta() -> Bool {
        return UserDefaults.standard.bool(forKey: betaOptInKey)
    }
    
    func checkForBetaUpdates(force: Bool = false) {
        guard isOptedIntoBeta() else { return }
        
        let lastCheck = UserDefaults.standard.object(forKey: lastBetaCheckKey) as? Date ?? .distantPast
        if !force && Date().timeIntervalSince(lastCheck) < 3600 { return }
        
        UserDefaults.standard.set(Date(), forKey: lastBetaCheckKey)
        
        checkRemoteForChanges { [weak self] hasChanges, count, files in
            DispatchQueue.main.async {
                if hasChanges {
                    self?.betaUpdateAvailable = BetaUpdateInfo(
                        hasNewCommits: true,
                        commitCount: count,
                        latestCommit: nil,
                        changedFiles: files
                    )
                    self?.showBetaPrompt = true
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getCurrentAppVersion() -> AppVersion? {
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let bundleBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        
        let versionString = "AP\(bundleVersion)_AND0.\(bundleBuild)"
        return AppVersion(from: versionString) ?? AppVersion(from: "AP0.0_AND0.0")
    }
}

// MARK: - Update Info Models

struct UpdateInfo {
    let version: AppVersion
    let release: GitHubRelease
}

struct BetaUpdateInfo {
    let hasNewCommits: Bool
    let commitCount: Int
    let latestCommit: GitHubCommit?
    let changedFiles: [String]?
}

// MARK: - Update Prompt View

struct UpdatePromptView: View {
    @Environment(\.dismiss) private var dismiss
    let updateInfo: UpdateInfo
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 70))
                        .foregroundColor(.blue)
                        .padding(.top, 20)
                    
                    Text("New Version Available!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    
                    Text("Version \(updateInfo.version.stringValue)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    if let releaseNotes = updateInfo.release.body {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What's New:")
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            Text(releaseNotes)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Install Options:")
                            .font(.headline)
                        
                        Button {
                            if let url = URL(string: "https://nikos-projects.github.io/ipa-distributor") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text("OTA Installer")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Install directly (requires device registration)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            if let url = URL(string: updateInfo.release.html_url) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "link.circle")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text("GitHub Release Page")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Download IPA manually")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Dismiss") {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(false)
    }
}

// MARK: - Beta Update Prompt View

struct BetaUpdatePromptView: View {
    @Environment(\.dismiss) private var dismiss
    let betaInfo: BetaUpdateInfo
    @ObservedObject private var updateChecker = UpdateChecker.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "hammer.circle.fill")
                        .font(.system(size: 70))
                        .foregroundColor(.orange)
                        .padding(.top, 20)
                    
                    Text("Beta Update Available!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    
                    Text("New development work detected")
                        .font(.title3)
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.green)
                            Text("\(betaInfo.commitCount) file\(betaInfo.commitCount > 1 ? "s" : "") changed")
                                .font(.body)
                        }
                        
                        if let files = betaInfo.changedFiles, !files.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Changed files:")
                                    .font(.headline)
                                    .padding(.top, 8)
                                
                                ForEach(files.prefix(5), id: \.self) { file in
                                    HStack {
                                        Image(systemName: "doc")
                                            .font(.caption)
                                        Text(file)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                if files.count > 5 {
                                    Text("...and \(files.count - 5) more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What would you like to do?")
                            .font(.headline)
                        
                        Button {
                            updateChecker.downloadAndCompareRepository { progress, status in
                                // Update UI if needed
                            } completion: { success, hasChanges, error in
                                if success {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.doc")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text("Fetch Latest Changes")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Update cached file information")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            updateChecker.checkForUpdates(force: true)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text("Check for Release")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("See if a stable version is available")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            if let url = URL(string: "https://github.com/nikos-projects/playbox") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "link.circle")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text("View Repository")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("See changes on GitHub")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .font(.title2)
                                Text("Dismiss")
                                    .font(.system(size: 16, weight: .semibold))
                                Spacer()
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Dismiss") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Beta Opt-In View

struct BetaOptInView: View {
    @AppStorage("betaOptIn") private var betaOptIn = false
    @AppStorage("hasSeenBetaPrompt") private var hasSeenBetaPrompt = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var updateChecker = UpdateChecker.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "flask.circle.fill")
                    .font(.system(size: 70))
                    .foregroundColor(.orange)
                    .padding(.top, 40)
                
                Text("Beta Updates")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                
                Text("Would you like to be notified about beta development?")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("Get early access to new features", systemImage: "star.fill")
                        .foregroundColor(.green)
                    Label("Help shape the app's direction", systemImage: "hand.thumbsup.fill")
                        .foregroundColor(.blue)
                    Label("Report bugs before public release", systemImage: "ant.fill")
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                WarningCard()
                    .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button {
                        betaOptIn = true
                        hasSeenBetaPrompt = true
                        updateChecker.optIntoBetaTracking()
                        updateChecker.performInitialDownload()
                        dismiss()
                    } label: {
                        Text("Yes, Track Beta Updates")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        betaOptIn = false
                        hasSeenBetaPrompt = true
                        dismiss()
                    } label: {
                        Text("No, Thanks")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip for Now") {
                        hasSeenBetaPrompt = true
                        dismiss()
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

struct WarningCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("Storage & Data Warning")
                    .font(.headline)
                    .foregroundColor(.yellow)
            }
            
            Text("Beta tracking will:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            BulletPoint(text: "Store file hashes for comparison (not full files)")
            BulletPoint(text: "Use ~5-10MB of additional storage")
            BulletPoint(text: "Make API calls to GitHub regularly")
            BulletPoint(text: "Notify you when remote files change")
            BulletPoint(text: "Never download full source code (just metadata)")
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }
}

struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.yellow)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}
