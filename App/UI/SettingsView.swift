import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showConnectSheet = false
    @State private var confirmReset = false
    @State private var confirmDemoEnd = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                connectionSection
                syncSection
                calculationSection(model: $model)
                demoSection
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("More")
            .sheet(isPresented: $showConnectSheet) {
                ConnectSheet()
            }
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.isConnected ? Theme.green : Theme.textSecondary)
                        .frame(width: 8, height: 8)
                    Text(model.isConnected ? "Connected" : "Not connected")
                }
            }
            if let name = model.profileName {
                LabeledContent("Account", value: name)
            }
            Button(model.isConnected ? "Reconnect" : "Connect to Google Health") {
                showConnectSheet = true
            }
            if model.isConnected {
                Button("Disconnect", role: .destructive) {
                    model.disconnect()
                }
            }
        } header: {
            Text("Google Health")
        } footer: {
            Text("Note: As long as your Google Cloud project is in 'Testing' status, the login expires every 7 days and must be renewed via 'Reconnect'.")
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        @Bindable var model = model
        return Section("Synchronization") {
            Button {
                Task { await model.syncNow() }
            } label: {
                HStack {
                    Text(model.syncing ? model.syncMessage : "Sync now")
                    Spacer()
                    if model.syncing {
                        ProgressView()
                    }
                }
            }
            .disabled(!model.isConnected || model.syncing)

            if let lastSync = model.lastSyncAt {
                LabeledContent("Last sync", value: Fmt.relative(lastSync))
            }

            Picker("Timeframe (Backfill)", selection: $model.daysBack) {
                Text("30 Days").tag(30)
                Text("60 Days").tag(60)
                Text("90 Days").tag(90)
                Text("180 Days").tag(180)
            }
            Picker("Intraday Heart Rate", selection: $model.hrDaysBack) {
                Text("7 Days").tag(7)
                Text("14 Days").tag(14)
                Text("28 Days").tag(28)
            }

            NavigationLink("Sync Log") {
                SyncLogView()
            }
        }
    }

    // MARK: - Calculation

    private func calculationSection(model: Bindable<AppModel>) -> some View {
        Section {
            Stepper(value: model.baseSleepNeedMinutes, in: 360...600, step: 15) {
                LabeledContent("Baseline Sleep Need", value: "\(Fmt.hm(model.wrappedValue.baseSleepNeedMinutes)) h")
            }
            Stepper(value: model.age, in: 14...90) {
                LabeledContent("Age", value: "\(model.wrappedValue.age)")
            }
            if model.wrappedValue.maxHROverride > 0 {
                Stepper(value: model.maxHROverride, in: 130...220, step: 1) {
                    LabeledContent("Max Heart Rate", value: "\(Int(model.wrappedValue.maxHROverride))")
                }
                Button("Determine Max HR automatically") {
                    model.wrappedValue.maxHROverride = 0
                }
            } else {
                LabeledContent("Max Heart Rate", value: "\(Int(model.wrappedValue.strainConfig.maxHR)) (automatic)")
                Button("Set Max HR manually") {
                    model.wrappedValue.maxHROverride = model.wrappedValue.strainConfig.maxHR.rounded()
                }
            }
        } header: {
            Text("Calculation")
        } footer: {
            Text("Max HR automatic = Tanaka formula (208 − 0.7 × age). All scores are immediately recalculated upon changes.")
        }
    }

    // MARK: - Demo

    private var demoSection: some View {
        Section("Demo Mode") {
            if model.demoMode {
                LabeledContent("Status", value: "Active (generated data)")
                Button("End demo & delete data", role: .destructive) {
                    confirmDemoEnd = true
                }
                .confirmationDialog("Really delete demo data?", isPresented: $confirmDemoEnd, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        model.resetAll()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } else {
                Button("Load demo data") {
                    model.startDemo()
                }
                .disabled(model.isConnected)
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            Button("Delete all data", role: .destructive) {
                confirmReset = true
            }
            .confirmationDialog(
                "Delete all local data and the Google connection?",
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    model.disconnect()
                    model.resetAll()
                }
                Button("Cancel", role: .cancel) {}
            }
        } footer: {
            Text("All data is stored exclusively locally on this iPhone (JSON in Application Support). There is no server.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "Pulse 1.0")
            LabeledContent("Data Source", value: "Google Health API (v4)")
            Text("Pulse reads the data from your Fitbit Air via the Google Health API (successor to the Fitbit Web API, which will be shut down in September 2026) and calculates Whoop-like recovery, strain, and sleep scores from it – purely locally, without a subscription.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Sync Log

struct SyncLogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.syncLog.isEmpty {
                Text("No sync in this session yet.")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(model.syncLog) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(entry.isError ? Theme.yellow : Theme.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.metric)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.detail)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Sync Log")
        .navigationBarTitleDisplayMode(.inline)
    }
}
