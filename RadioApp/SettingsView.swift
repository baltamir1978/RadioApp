import SwiftUI

private let accent = Color.brand

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
                            // Formatted rather than "\(n) s" so the unit follows the locale.
                            Text(Measurement(value: player.bufferDuration, unit: UnitDuration.seconds)
                                .formatted(.measurement(width: .abbreviated,
                                                        usage: .asProvided,
                                                        numberFormatStyle: .number.precision(.fractionLength(0)))))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .accessibilityHidden(true)
                        }
                        Slider(value: $player.bufferDuration, in: 2...60, step: 1)
                            .tint(accent)
                            .accessibilityLabel(NSLocalizedString("settings_buffer", comment: ""))
                            // Without this VoiceOver reads a bare percentage, not seconds.
                            .accessibilityValue(String(format: NSLocalizedString("a11y_buffer_value", comment: ""),
                                                       Int(player.bufferDuration)))
                            .accessibilityHint(NSLocalizedString("a11y_buffer_hint", comment: ""))
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
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("settings_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.mintSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("close", comment: "")) { dismiss() }
                }
            }
        }
        .tint(accent)
    }
}
