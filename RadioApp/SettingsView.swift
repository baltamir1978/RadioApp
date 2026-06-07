import SwiftUI

private let accent = Color(hex: "#FF6B35")

struct SettingsView: View {
    @ObservedObject private var player = RadioPlayer.shared
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Audio buffer
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("settings_buffer", comment: ""))
                            Spacer()
                            Text("\(Int(player.bufferDuration)) s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $player.bufferDuration, in: 2...60, step: 1)
                            .tint(accent)
                        HStack {
                            Text(NSLocalizedString("settings_buffer_fast", comment: ""))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(NSLocalizedString("settings_buffer_stable", comment: ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text(NSLocalizedString("settings_buffer_footer", comment: ""))
                }

                // MARK: About
                Section {
                    HStack {
                        Text(NSLocalizedString("settings_version", comment: ""))
                        Spacer()
                        Text(appVersion).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("settings_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("close", comment: "")) { dismiss() }
                }
            }
        }
        .tint(accent)
    }
}
