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

// MARK: - Version Parser

struct AppVersion: Comparable {
    let platform: String  // "AP" for Apple, "AND" for Android
    let major: Int
    let minor: Int
    let patch: Int
    
    init?(from tag: String) {
        // Format: AP4.5_AND0.6 or AP1.2.3_AND1.2.3
        let components = tag.split(separator: "_")
        guard components.count == 2 else { return nil }
        
        func parseVersion(_ versionStr: String) -> (platform: String, major: Int, minor: Int, patch: Int)? {
            // Extract platform prefix (AP or AND)
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
        
        guard let apVersion = parseVersion(String(components[0])),
              let andVersion = parseVersion(String(components[1])) else { return nil }
        
        self.platform = "AP"  // We only care about Apple platform
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

// MARK: - Update Checker

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    
    @Published var isChecking = false
    @Published var updateAvailable: UpdateInfo?
    @Published var betaUpdateAvailable: BetaUpdateInfo?
    @Published var showUpdatePrompt = false
    @Published var showBetaPrompt = false
    
    let repoOwner = "nikos-projects"
    let repoName = "playbox"
    let userDefaultsKey = "lastUpdateCheck"
    let betaOptInKey = "betaOptIn"
    let lastBetaCheckKey = "lastBetaCheck"
    let lastCommitShaKey = "lastCommitSha"
    
    private var checkTimer: Timer?
    
    private init() {
        startPeriodicChecks()
    }
    
    deinit {
        checkTimer?.invalidate()
    }
    
    private func startPeriodicChecks() {
        // Check every 24 hours
        checkTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
            if UserDefaults.standard.bool(forKey: self?.betaOptInKey ?? "") {
                self?.checkForBetaUpdates()
            }
        }
    }
    
    // MARK: - Release Check
    
    func checkForUpdates(force: Bool = false) {
        let lastCheck = UserDefaults.standard.object(forKey: userDefaultsKey) as? Date ?? .distantPast
        if !force && Date().timeIntervalSince(lastCheck) < 3600 { return } // Don't check more than once per hour
        
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
                    
                    // Find latest non-prerelease release
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
    
    // MARK: - Beta Check
    
    func optIntoBetaTracking() {
        UserDefaults.standard.set(true, forKey: betaOptInKey)
        checkForBetaUpdates(force: true)
    }
    
    func optOutOfBetaTracking() {
        UserDefaults.standard.set(false, forKey: betaOptInKey)
        UserDefaults.standard.removeObject(forKey: lastCommitShaKey)
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
        
        // Get latest commits from main branch
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/commits?per_page=5"
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            
            do {
                let commits = try JSONDecoder().decode([GitHubCommit].self, from: data)
                guard let latestCommit = commits.first else { return }
                
                DispatchQueue.main.async {
                    self?.checkForBetaWork(commits: commits, latestCommit: latestCommit)
                }
            } catch {
                print("Failed to decode commits: \(error)")
            }
        }.resume()
    }
    
    private func checkForBetaWork(commits: [GitHubCommit], latestCommit: GitHubCommit) {
        let lastCommitSha = UserDefaults.standard.string(forKey: lastCommitShaKey)
        
        if lastCommitSha == nil {
            // First time - store current commit
            UserDefaults.standard.set(latestCommit.sha, forKey: lastCommitShaKey)
            return
        }
        
        if lastCommitSha != latestCommit.sha {
            // New commits detected - check recency
            let commitDate = ISO8601DateFormatter().date(from: latestCommit.commit.author.date) ?? Date()
            let daysSinceCommit = Calendar.current.dateComponents([.day], from: commitDate, to: Date()).day ?? 0
            
            if daysSinceCommit <= 7 {
                // Find if there's a release in progress (check for prerelease tags)
                let releaseUrlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases"
                if let url = URL(string: releaseUrlString) {
                    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                        if let data = data,
                           let releases = try? JSONDecoder().decode([GitHubRelease].self, from: data) {
                            let prerelease = releases.first { $0.prerelease }
                            DispatchQueue.main.async {
                                self?.betaUpdateAvailable = BetaUpdateInfo(
                                    hasNewCommits: true,
                                    commitCount: commits.count,
                                    latestCommit: latestCommit,
                                    prerelease: prerelease
                                )
                                self?.showBetaPrompt = true
                            }
                        }
                    }.resume()
                } else {
                    betaUpdateAvailable = BetaUpdateInfo(
                        hasNewCommits: true,
                        commitCount: commits.count,
                        latestCommit: latestCommit,
                        prerelease: nil
                    )
                    showBetaPrompt = true
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getCurrentAppVersion() -> AppVersion? {
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let bundleBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        
        // Try to parse from build settings or use a default
        // In a real app, you'd set this in your build script
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
    let latestCommit: GitHubCommit
    let prerelease: GitHubRelease?
}

// MARK: - Update Prompt View

struct UpdatePromptView: View {
    @Environment(\.dismiss) private var dismiss
    let updateInfo: UpdateInfo
    @State private var showingOTADownload = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
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
                    
                    // Release notes
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
                    
                    // Install options
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
                            Image(systemName: "clock.fill")
                                .foregroundColor(.blue)
                            Text("Recent commits found in the last 7 days")
                                .font(.body)
                        }
                        
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.green)
                            Text("\(betaInfo.commitCount) new commit\(betaInfo.commitCount > 1 ? "s" : "") since your last check")
                                .font(.body)
                        }
                        
                        if let prerelease = betaInfo.prerelease {
                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundColor(.purple)
                                Text("Prerelease: \(prerelease.tag_name)")
                                    .font(.body)
                            }
                        }
                        
                        Divider()
                        
                        Text("Latest commit:")
                            .font(.headline)
                        
                        Text(betaInfo.latestCommit.commit.message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.leading)
                        
                        Text("by \(betaInfo.latestCommit.commit.author.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What would you like to do?")
                            .font(.headline)
                        
                        Button {
                            if let url = URL(string: "https://github.com/\(updateChecker.repoOwner)/\(updateChecker.repoName)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.doc")
                                    .font(.title2)
                                VStack(alignment: .leading) {
                                    Text("View Repository")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("See what's being worked on")
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
                    
                    Text("Tip: You can disable beta tracking in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top)
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
                        UpdateChecker.shared.optIntoBetaTracking()
                        dismiss()
                    } label: {
                        Text("Yes, Notify Me")
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
                Text("Important Note")
                    .font(.headline)
                    .foregroundColor(.yellow)
            }
            
            Text("Beta tracking may:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            BulletPoint(text: "Increase app storage usage by up to 3x or more")
            BulletPoint(text: "Include unstable or unfinished features")
            BulletPoint(text: "Cause occasional crashes or data loss")
            BulletPoint(text: "Require more frequent updates")
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
