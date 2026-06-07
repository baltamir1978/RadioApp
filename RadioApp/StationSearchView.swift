import SwiftUI

struct StationSearchView: View {
    @EnvironmentObject var store: StationsStore
    @EnvironmentObject var player: RadioPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedCountry = ""
    @State private var results: [RadioBrowserStation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let countries: [(String, String)] = [
        ("", "Todos"),
        ("ES", "España 🇪🇸"),
        ("GB", "Reino Unido 🇬🇧"),
        ("US", "Estados Unidos 🇺🇸"),
        ("FR", "Francia 🇫🇷"),
        ("DE", "Alemania 🇩🇪"),
        ("IT", "Italia 🇮🇹"),
        ("PT", "Portugal 🇵🇹"),
        ("MX", "México 🇲🇽"),
        ("AR", "Argentina 🇦🇷"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("País", selection: $selectedCountry) {
                    ForEach(countries, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                Group {
                    if isLoading {
                        ProgressView(NSLocalizedString("searching", comment: ""))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let err = errorMessage {
                        ContentUnavailableView(
                            NSLocalizedString("search_error", comment: ""),
                            systemImage: "wifi.slash",
                            description: Text(err)
                        )
                    } else if results.isEmpty && !query.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        List(results) { station in
                            SearchResultRow(browserStation: station)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("search_stations", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: NSLocalizedString("search_prompt", comment: ""))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("close", comment: "")) { dismiss() }
                }
            }
            .onSubmit(of: .search) {
                Task { await performSearch() }
            }
            .onChange(of: selectedCountry) { _, _ in
                Task { await performSearch() }
            }
            .task { await performSearch() }
        }
    }

    private func performSearch() async {
        isLoading = true
        errorMessage = nil
        do {
            let country = selectedCountry.isEmpty ? nil : selectedCountry
            if query.isEmpty {
                results = try await RadioBrowserService.shared.topStations(country: country)
            } else {
                results = try await RadioBrowserService.shared.search(name: query, country: country)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct SearchResultRow: View {
    @EnvironmentObject var store: StationsStore
    @EnvironmentObject var player: RadioPlayer
    let browserStation: RadioBrowserStation

    private var station: Station { browserStation.toStation }
    private var isAdded: Bool { store.contains(station) }

    var body: some View {
        HStack(spacing: 12) {
            StationLogo(station: station, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(station.name)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let country = station.country {
                        Text(country)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                    if let genre = station.genre {
                        Text(genre)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button {
                player.play(station)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            Button {
                store.add(station)
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(isAdded ? Color.green : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
        }
        .padding(.vertical, 2)
    }
}
