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
    @AppStorage("solitaireTapMode") private var solitaireTapMode: String = "tap"
    @State private var showingBetaOptIn = false
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Control Style")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)

                        Picker("Control Style", selection: $solitaireTapMode) {
                            Label("Tap to Select", systemImage: "hand.tap")
                                .tag("tap")
                            Label("Auto Move", systemImage: "wand.and.sparkles")
                                .tag("auto")
                        }
                        .pickerStyle(.segmented)

                        Text(solitaireTapMode == "auto"
                             ? "Tap any card to automatically move it to the best available position."
                             : "Tap a card to select it, then tap a destination to move it.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Solitaire", systemImage: "suit.spade.fill")
                }

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
                                    Text("\(betaInfo.commitCount) file\(betaInfo.commitCount > 1 ? "s" : "") changed")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
                            Text("Beta tracking stores file hashes (~5-10MB)")
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
                
                if let files = betaInfo.changedFiles, !files.isEmpty {
                    changedFilesSection(files: files)
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
                Text("Beta Development Detected")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text("\(betaInfo.commitCount) file\(betaInfo.commitCount > 1 ? "s have" : " has") changed since your last check")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func changedFilesSection(files: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Changed Files:")
                .font(.headline)
            
            ForEach(files.prefix(10), id: \.self) { file in
                HStack {
                    Image(systemName: "doc")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(file)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            if files.count > 10 {
                Text("...and \(files.count - 10) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
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
                UpdateChecker.shared.fetchAndCompareRepository { progress, status in
                    // Progress handled by update checker
                } completion: { success, hasChanges, files, error in
                    if success {
                        // Refresh - could trigger a reload of the view
                    }
                }
            } label: {
                Label("Refresh File Cache", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
            }
            
            Button {
                if let url = URL(string: "https://github.com/nikos-projects/playbox") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("View Repository on GitHub", systemImage: "link")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
            }
        }
        .buttonStyle(.plain)
    }
}
