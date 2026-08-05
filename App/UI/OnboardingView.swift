import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var showConnectSheet = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.teal.opacity(0.25), Theme.sleepPurple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 130, height: 130)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(Theme.teal)
                }
                .padding(.bottom, 24)

                Text("Pulse")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your personal recovery system\nfor the Fitbit Air")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 14) {
                    featureRow(icon: "arrow.clockwise.heart.fill", color: Theme.green,
                               title: "Recovery Score",
                               text: "HRV, resting HR, sleep, and respiratory rate against your personal baseline.")
                    featureRow(icon: "flame.fill", color: Theme.strainBlue,
                               title: "Strain 0–21",
                               text: "Cardiovascular load from your heart rate zones, like Whoop.")
                    featureRow(icon: "bed.double.fill", color: Theme.sleepPurple,
                               title: "Sleep Need & Debt",
                               text: "How much sleep you really need today – including stage analysis.")
                }
                .padding(24)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showConnectSheet = true
                    } label: {
                        Text("Connect to Google Health")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.teal))
                            .foregroundStyle(Color.black)
                    }
                    Button {
                        model.startDemo()
                    } label: {
                        Text("Start with demo data for now")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showConnectSheet) {
            ConnectSheet()
        }
    }

    private func featureRow(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Connection sheet: Enter client ID + start OAuth flow.
struct ConnectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. 1234567890-abc.apps.googleusercontent.com", text: $model.clientID, axis: .vertical)
                        .font(.footnote.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("iOS Client ID (Google Cloud)")
                } footer: {
                    Text("Required once: Enable the **Google Health API** in the Google Cloud Console, create an OAuth client of type **iOS**, and paste the client ID here. Step-by-step instructions in the project's README.")
                }

                Section {
                    Button {
                        working = true
                        Task {
                            await model.connect()
                            working = false
                            if model.isConnected {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if working {
                                ProgressView().padding(.trailing, 6)
                            }
                            Text(working ? "Connecting…" : "Sign in with Google")
                        }
                    }
                    .disabled(working || !model.oauthConfig.isValid)
                } footer: {
                    if !model.clientID.isEmpty && !model.oauthConfig.isValid {
                        Text("The client ID must end with .apps.googleusercontent.com.")
                            .foregroundStyle(Theme.red)
                    }
                }

                if let error = model.lastError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.red)
                    }
                }
            }
            .navigationTitle("Google Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
