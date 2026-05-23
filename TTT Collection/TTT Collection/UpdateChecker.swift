//
//  UpdateChecker.swift
//  TTT Collection
//
//  Created on 2026-05-22.
//

import Foundation
import SwiftUI
internal import Combine

// MARK: - GitHub API Models

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
    let files: [String: String]
    let lastUpdated: Date
}

// MARK: - Update Checker

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
    
    private let repoOwner = "nikos-projects"
    private let repoName = "playbox"
    private let userDefaultsKey = "lastUpdateCheck"
    private let betaOptInKey = "betaOptIn"
    private let lastBetaCheckKey = "lastBetaCheck"
    private let fileHashCacheKey = "fileHashCache"
    
    private var checkTimer: Timer?
    private var downloadedFileHashes: [String: String] = [:]
    private var lastCommitSha: String = ""
    
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
    
    // MARK: - Persistence
    
    private func loadFileHashCache() {
        if let data = UserDefaults.standard.data(forKey: fileHashCacheKey),
           let cache = try? JSONDecoder().decode(FileHashCache.self, from: data) {
            downloadedFileHashes = cache.files
            lastCommitSha = cache.commitSha
            print("Loaded cache with \(downloadedFileHashes.count) files from commit \(lastCommitSha.prefix(7))")
        } else {
            print("No existing cache found")
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
            print("Saved cache with \(downloadedFileHashes.count) files for commit \(commitSha.prefix(7))")
        }
    }
    
    // MARK: - Fetch and Compare Repository
    
    func fetchAndCompareRepository(progress: @escaping (Double, String) -> Void, completion: @escaping (Bool, Bool, [String]?, Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            progress(0.05, "Fetching repository file tree from GitHub...")
            
            // Get the repository file tree
            let treeURL = URL(string: "https://api.github.com/repos/\(self.repoOwner)/\(self.repoName)/git/trees/main?recursive=1")!
            
            var request = URLRequest(url: treeURL)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            
            let semaphore = DispatchSemaphore(value: 0)
            var tree: GitHubTree?
            var networkError: Error?
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                networkError = error
                if let data = data {
                    do {
                        tree = try JSONDecoder().decode(GitHubTree.self, from: data)
                        print("Successfully fetched tree with \(tree?.tree.count ?? 0) items")
                    } catch {
                        print("Failed to decode tree: \(error)")
                        networkError = error
                    }
                }
                semaphore.signal()
            }.resume()
            
            semaphore.wait()
            
            guard let tree = tree, networkError == nil else {
                DispatchQueue.main.async {
                    completion(false, false, nil, networkError)
                }
                return
            }
            
            progress(0.2, "Analyzing \(tree.tree.count) files...")
            
            // Filter for relevant files
            let relevantFiles = tree.tree.filter { item in
                let ext = (item.path as NSString).pathExtension
                return ext == "swift" ||
                       ext == "xcodeproj" ||
                       ext == "xcworkspace" ||
                       item.path.contains(".pbxproj") ||
                       ext == "txt" ||
                       ext == "md"
            }
            
            print("Found \(relevantFiles.count) relevant files")
            
            var newHashes: [String: String] = [:]
            var changedFiles: [String] = []
            var totalProcessed = 0
            
            for file in relevantFiles {
                totalProcessed += 1
                let percent = 0.2 + (Double(totalProcessed) / Double(relevantFiles.count)) * 0.7
                progress(percent, "Checking: \(file.path)")
                
                newHashes[file.path] = file.sha
                
                // Compare with cached hash
                if let cachedHash = self.downloadedFileHashes[file.path] {
                    if cachedHash != file.sha {
                        changedFiles.append(file.path)
                        print("Changed: \(file.path) (\(cachedHash.prefix(7)) -> \(file.sha.prefix(7)))")
                    }
                } else {
                    // New file not in cache
                    changedFiles.append(file.path)
                    print("New file: \(file.path)")
                }
            }
            
            // Update cache
            let hasChanges = !changedFiles.isEmpty
            self.downloadedFileHashes = newHashes
            self.saveFileHashCache(commitSha: tree.sha)
            
            progress(1.0, hasChanges ? "Found \(changedFiles.count) changes" : "No changes detected")
            
            DispatchQueue.main.async {
                completion(true, hasChanges, changedFiles, nil)
                
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
    
    // MARK: - Quick Remote Check
    
    func checkForRemoteChanges(completion: @escaping (Bool, Int, [String]?) -> Void) {
        print("Checking for remote changes...")
        
        let treeURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/git/trees/main?recursive=1")!
        
        var request = URLRequest(url: treeURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                print("Network error: \(error?.localizedDescription ?? "unknown")")
                completion(false, 0, nil)
                return
            }
            
            do {
                let tree = try JSONDecoder().decode(GitHubTree.self, from: data)
                print("Fetched tree with \(tree.tree.count) total items")
                
                let relevantFiles = tree.tree.filter { item in
                    let ext = (item.path as NSString).pathExtension
                    return ext == "swift" ||
                           ext == "xcodeproj" ||
                           item.path.contains(".pbxproj")
                }
                
                print("Found \(relevantFiles.count) relevant files")
                
                var changedFiles: [String] = []
                for file in relevantFiles {
                    if let cachedHash = self?.downloadedFileHashes[file.path], cachedHash != file.sha {
                        changedFiles.append(file.path)
                        print("Change detected: \(file.path)")
                    } else if self?.downloadedFileHashes[file.path] == nil {
                        changedFiles.append(file.path)
                        print("New file detected: \(file.path)")
                    }
                }
                
                print("Total changes found: \(changedFiles.count)")
                completion(!changedFiles.isEmpty, changedFiles.count, changedFiles)
                
            } catch {
                print("Failed to decode: \(error)")
                completion(false, 0, nil)
            }
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
                guard let data = data, error == nil else {
                    print("Release check failed: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                
                do {
                    let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                    let currentVersion = self?.getCurrentAppVersion()
                    
                    let latestRelease = releases.first { !$0.prerelease }
                    
                    if let release = latestRelease,
                       let releaseVersion = AppVersion(from: release.tag_name),
                       let current = currentVersion {
                        
                        print("Current version: \(current.stringValue), Latest: \(releaseVersion.stringValue)")
                        
                        if releaseVersion > current {
                            print("New version available!")
                            self?.updateAvailable = UpdateInfo(
                                version: releaseVersion,
                                release: release
                            )
                            self?.showUpdatePrompt = true
                        } else {
                            print("App is up to date")
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
    
    func performInitialFetch() {
        isDownloading = true
        fetchAndCompareRepository { [weak self] progress, status in
            DispatchQueue.main.async {
                self?.downloadProgress = progress
                self?.downloadStatus = status
            }
        } completion: { [weak self] success, hasChanges, files, error in
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
        downloadedFileHashes.removeAll()
        lastCommitSha = ""
        betaUpdateAvailable = nil
        print("Opted out of beta tracking, cache cleared")
    }
    
    func isOptedIntoBeta() -> Bool {
        return UserDefaults.standard.bool(forKey: betaOptInKey)
    }
    
    func checkForBetaUpdates(force: Bool = false) {
        guard isOptedIntoBeta() else {
            print("Not opted into beta")
            return
        }
        
        let lastCheck = UserDefaults.standard.object(forKey: lastBetaCheckKey) as? Date ?? .distantPast
        if !force && Date().timeIntervalSince(lastCheck) < 3600 {
            print("Skipping beta check - last check was \(lastCheck)")
            return
        }
        
        UserDefaults.standard.set(Date(), forKey: lastBetaCheckKey)
        print("Checking for beta updates...")
        
        checkForRemoteChanges { [weak self] hasChanges, count, files in
            DispatchQueue.main.async {
                if hasChanges {
                    print("Beta changes found: \(count) files")
                    self?.betaUpdateAvailable = BetaUpdateInfo(
                        hasNewCommits: true,
                        commitCount: count,
                        latestCommit: nil,
                        changedFiles: files
                    )
                    self?.showBetaPrompt = true
                } else {
                    print("No beta changes found")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getCurrentAppVersion() -> AppVersion? {
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let bundleBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        
        let versionString = "AP\(bundleVersion)_AND0.\(bundleBuild)"
        print("Current app version string: \(versionString)")
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
                    
                    Text("Beta Changes Detected!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    
                    Text("\(betaInfo.commitCount) file\(betaInfo.commitCount > 1 ? "s have" : " has") changed")
                        .font(.title3)
                        .foregroundColor(.orange)
                    
                    if let files = betaInfo.changedFiles, !files.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Changed files:")
                                .font(.headline)
                            
                            ForEach(files.prefix(10), id: \.self) { file in
                                HStack {
                                    Image(systemName: "doc.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    Text(file)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                            
                            if files.count > 10 {
                                Text("...and \(files.count - 10) more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What would you like to do?")
                            .font(.headline)
                        
                        Button {
                            updateChecker.fetchAndCompareRepository { progress, status in
                                // Progress handled
                            } completion: { success, hasChanges, files, error in
                                if success {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text("Refresh & Update Cache")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Fetch latest file hashes")
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
                                    Text("Check for Stable Release")
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
                                Text("View on GitHub")
                                    .font(.system(size: 16, weight: .semibold))
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
                
                Text("Track file changes in the GitHub repository")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("Get notified when code changes", systemImage: "bell.fill")
                        .foregroundColor(.green)
                    Label("See which files were modified", systemImage: "doc.text.magnifyingglass")
                        .foregroundColor(.blue)
                    Label("Stay ahead of new features", systemImage: "star.fill")
                        .foregroundColor(.yellow)
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
                        updateChecker.performInitialFetch()
                        dismiss()
                    } label: {
                        Text("Yes, Track Beta Changes")
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
                Text("How Beta Tracking Works")
                    .font(.headline)
                    .foregroundColor(.yellow)
            }
            
            Text("When you opt in:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            BulletPoint(text: "App fetches the file list from GitHub (not full files)")
            BulletPoint(text: "Stores file hashes to detect changes (~5-10MB)")
            BulletPoint(text: "Checks for changes every 24 hours")
            BulletPoint(text: "Shows which files were added/modified")
            BulletPoint(text: "Never downloads your personal data")
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
