//
//  SettingsView.swift
//  TTT Collection
//
//  Created on 2026-05-22.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @AppStorage("betaOptIn") private var betaOptIn = false
    @State private var showingBetaOptIn = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Updates") {
                    HStack {
                        Text("Current Version")
                        Spacer()
                        Text(getCurrentVersionString())
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        updateChecker.checkForUpdates(force: true)
                    } label: {
                        HStack {
                            Text("Check for Updates")
                            Spacer()
                            if updateChecker.isChecking {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    
                    Toggle("Beta Tracking", isOn: Binding(
                        get: { betaOptIn },
                        set: { newValue in
                            if newValue {
                                showingBetaOptIn = true
                            } else {
                                betaOptIn = false
                                updateChecker.optOutOfBetaTracking()
                            }
                        }
                    ))
                    
                    if betaOptIn {
                        Button("Check for Beta Updates") {
                            updateChecker.checkForBetaUpdates(force: true)
                        }
                        
                        if let betaInfo = updateChecker.betaUpdateAvailable {
                            NavigationLink {
                                BetaUpdateDetailView(betaInfo: betaInfo)
                            } label: {
                                HStack {
                                    Image(systemName: "hammer.fill")
                                        .foregroundColor(.orange)
                                    Text("Beta Update Available")
                                        .foregroundColor(.orange)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section("About") {
                    Link(destination: URL(string: "https://github.com/nikos-projects/playbox")!) {
                        Label("GitHub Repository", systemImage: "link")
                    }
                    
                    Link(destination: URL(string: "https://github.com/nikos-projects/playbox/releases")!) {
                        Label("Releases", systemImage: "tag")
                    }
                    
                    Link(destination: URL(string: "https://nikos-projects.github.io/ipa-distributor")!) {
                        Label("OTA Installer", systemImage: "arrow.down.circle")
                    }
                }
                
                Section("Storage") {
                    HStack {
                        Text("App Size")
                        Spacer()
                        Text(getAppSize())
                            .foregroundColor(.secondary)
                    }
                    
                    if betaOptIn {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("Beta tracking may increase storage")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingBetaOptIn) {
                BetaOptInView()
            }
            .sheet(isPresented: $updateChecker.showUpdatePrompt) {
                if let updateInfo = updateChecker.updateAvailable {
                    UpdatePromptView(updateInfo: updateInfo)
                }
            }
            .sheet(isPresented: $updateChecker.showBetaPrompt) {
                if let betaInfo = updateChecker.betaUpdateAvailable {
                    BetaUpdatePromptView(betaInfo: betaInfo)
                }
            }
        }
    }
    
    private func getCurrentVersionString() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
    
    private func getAppSize() -> String {
        // Calculate app size from documents and caches
        let documentsSize = getDirectorySize(at: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let cachesSize = getDirectorySize(at: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let totalSize = documentsSize + cachesSize
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalSize))
    }
    
    private func getDirectorySize(at url: URL?) -> Int64 {
        guard let url = url else { return 0 }
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                do {
                    let attributes = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    total += Int64(attributes.fileSize ?? 0)
                } catch {
                    print("Error calculating size: \(error)")
                }
            }
        }
        return total
    }
}

struct BetaUpdateDetailView: View {
    let betaInfo: BetaUpdateInfo
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                commitSection
                if let prerelease = betaInfo.prerelease {
                    prereleaseSection(prerelease: prerelease)
                }
                actionSection
            }
            .padding()
        }
        .navigationTitle("Beta Update Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hammer.fill")
                    .foregroundColor(.orange)
                    .font(.title)
                Text("Beta Development In Progress")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text("The developer is actively working on new features")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var commitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest Commit")
                .font(.headline)
            
            Text(betaInfo.latestCommit.commit.message)
                .font(.body)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(8)
            
            HStack {
                Image(systemName: "person.circle.fill")
                Text(betaInfo.latestCommit.commit.author.name)
                Spacer()
                Text(formatDate(betaInfo.latestCommit.commit.author.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
            
            Link(destination: URL(string: betaInfo.latestCommit.html_url)!) {
                Label("View on GitHub", systemImage: "link")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func prereleaseSection(prerelease: GitHubRelease) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prerelease Available")
                .font(.headline)
            
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(.purple)
                Text(prerelease.tag_name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            if let body = prerelease.body {
                Text(body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            
            Link(destination: URL(string: prerelease.html_url)!) {
                Label("View Prerelease", systemImage: "link")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                UpdateChecker.shared.checkForUpdates(force: true)
            } label: {
                Label("Check for Stable Release", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
            }
            
            Button {
                if let url = URL(string: "https://github.com/nikos-projects/playbox") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("View Repository", systemImage: "folder")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}
