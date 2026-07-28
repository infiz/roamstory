import AuthenticationServices
import SwiftUI

struct SetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: AuthenticationStore
    @State private var isShowingAccountID = false
    @State private var isEditingNickname = false
    @State private var nickname = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Server", value: "roamstory.infiz.com")
                    if let account = authentication.account {
                        LabeledContent("Email") {
                            HStack(spacing: 6) {
                                Text(account.email)
                                Button {
                                    isShowingAccountID = true
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show account ID")
                            }
                        }
                        if let displayName = account.displayName, !displayName.isEmpty {
                            LabeledContent("Public Name", value: displayName)
                        }
                    }
                } header: {
                    Text("RoamStory Account")
                } footer: {
                    if authentication.account == nil {
                        Text("Sign in before sharing a trip. Your existing trips remain stored locally.")
                    } else {
                        Text("Signing out removes only this device’s server session. Local trips and media references are not changed.")
                    }
                }

                authenticationSections

                if authentication.isWorking {
                    Section {
                        HStack {
                            ProgressView()
                            Text(authentication.activityMessage ?? "Contacting RoamStory…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .id(authentication.account?.id)
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Sign In Unavailable",
                isPresented: Binding(
                    get: { authentication.errorMessage != nil },
                    set: { if !$0 { authentication.errorMessage = nil } }
                )
            ) {
                Button("OK") { authentication.errorMessage = nil }
            } message: {
                Text(authentication.errorMessage ?? "")
            }
            .alert(
                "Choose a Nickname?",
                isPresented: Binding(
                    get: { authentication.shouldPromptForNickname },
                    set: { if !$0 { authentication.dismissNicknamePrompt() } }
                )
            ) {
                TextField("Nickname", text: $nickname)
                Button("Use My Name") {
                    authentication.dismissNicknamePrompt()
                }
                Button("Save Nickname") {
                    Task { await authentication.updateNickname(nickname) }
                }
                .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Other users can see your public name with your likes. Enter a nickname if you prefer not to show the name from your sign-in provider.")
            }
            .alert("Update Nickname", isPresented: $isEditingNickname) {
                TextField("Nickname", text: $nickname)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    Task { await authentication.updateNickname(nickname) }
                }
                .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("This name will be shown to other users with your likes.")
            }
            .alert("Account ID", isPresented: $isShowingAccountID) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(authentication.account?.id.uuidString.lowercased() ?? "")
            }
        }
    }

    @ViewBuilder
    private var authenticationSections: some View {
        if authentication.account == nil {
            Section("Sign In or Register") {
                SignInWithAppleButton(.continue) { request in
                    authentication.prepareAppleRequest(request)
                } onCompletion: { result in
                    switch result {
                    case let .success(authorization):
                        Task { await authentication.signInWithApple(authorization: authorization) }
                    case let .failure(error):
                        authentication.handleAppleFailure(error)
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .disabled(authentication.isWorking)

                Button {
                    Task { await authentication.signInWithGoogle() }
                } label: {
                    Label("Continue with Google", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(authentication.isWorking)

                Button {
                    Task { await authentication.signInWithFacebook() }
                } label: {
                    Label("Continue with Facebook", systemImage: "person.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(authentication.isWorking)
            }
        } else {
            Section {
                Button {
                    nickname = authentication.account?.displayName ?? ""
                    isEditingNickname = true
                } label: {
                    LabeledContent(
                        "Nickname",
                        value: authentication.account?.displayName ?? "Set"
                    )
                }
                .foregroundStyle(.primary)
                .disabled(authentication.isWorking)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Your nickname is shown to other users with your likes. Set one if you prefer not to show the name from your sign-in provider.")
            }

            Section {
                Button("Log Out", role: .destructive) {
                    Task { await authentication.logout() }
                }
                .disabled(authentication.isWorking)
            }
        }
    }
}
