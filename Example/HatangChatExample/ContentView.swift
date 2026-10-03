import HatangChat
import SwiftUI

struct ContentView: View {
    let demo: Demo
    @State private var settings = false

    var body: some View {
        let model = HatangChat.model
        NavigationStack {
            List {
                Section {
                    Button("Open chat", systemImage: "bubble.left.and.bubble.right") { HatangChat.present() }
                    Button("Open inbox", systemImage: "tray") { HatangChat.presentInbox() }
                    Button("Identify demo user", systemImage: "person.crop.circle.badge.checkmark") { Task { await demo.identify() } }
                    Button("Reset", systemImage: "arrow.counterclockwise", role: .destructive) { Task { await demo.reset() } }
                    Button("Enable push", systemImage: "bell.badge") { Task { await demo.enablePush() } }
                }
                .disabled(!HatangChat.isConfigured)
                Section("Status") {
                    LabeledContent("SDK", value: demo.status)
                    LabeledContent("Connection", value: "\(model.phase) · \(model.connection)")
                    LabeledContent("Visitor", value: model.visitor?.id ?? "–")
                    LabeledContent("Conversation", value: model.conversation?.id ?? "–")
                    LabeledContent("Unread", value: "\(model.unread)")
                }
                .font(.footnote)
            }
            .navigationTitle(model.config?.name ?? "Hatang Chat")
            .toolbar {
                Button("Settings", systemImage: "gearshape") { settings = true }
            }
            .sheet(isPresented: $settings) { SettingsView(demo: demo) }
        }
        .overlay(alignment: .bottomTrailing) {
            HatangChatLauncher().padding(20)
        }
    }
}

struct SettingsView: View {
    @Bindable var demo: Demo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Gateway") {
                    TextField("Base URL", text: $demo.baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Site") {
                    TextField("Site id (site_…)", text: $demo.siteId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("App key (hak_…)", text: $demo.appKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        demo.save()
                        dismiss()
                    }
                    .disabled(!demo.canConfigure)
                }
            }
        }
    }
}
