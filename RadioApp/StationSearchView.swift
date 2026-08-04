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

    /// Country names come from the system so they follow the reader's language;
    /// only the codes live here. Sorted by the localized name, "All" first.
    private var countries: [CountryOption] {
        let codes = ["ES", "GB", "US", "FR", "DE", "IT", "PT", "MX", "AR"]
        return [CountryOption(code: "")] + codes
            .map(CountryOption.init)
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(NSLocalizedString("search_country", comment: ""), selection: $selectedCountry) {
                    ForEach(countries) { country in
                        Text(country.label).tag(country.code)
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

/// A country filter entry: the ISO code plus a name in the reader's language.
struct CountryOption: Identifiable {
    let code: String
    var id: String { code }

    var label: String {
        guard !code.isEmpty else { return NSLocalizedString("search_country_all", comment: "") }
        let name = Locale.current.localizedString(forRegionCode: code) ?? code
        return "\(name) \(flag)"
    }

    /// Regional indicator symbols: 'E','S' → 🇪🇸
    private var flag: String {
        code.unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map(String.init)
            .joined()
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
                .accessibilityHidden(true)

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
            // The name, country and genre read as one phrase instead of three stops.
            .accessibilityElement(children: .combine)

            Spacer()

            Button {
                player.play(station)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("a11y_play_station", comment: ""), station.name))

            Button {
                store.add(station)
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(isAdded ? Color.green : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
            .accessibilityLabel(isAdded
                                ? NSLocalizedString("a11y_station_added", comment: "")
                                : String(format: NSLocalizedString("a11y_add_station", comment: ""), station.name))
        }
        .padding(.vertical, 2)
    }
}
