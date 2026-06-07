import SwiftUI

struct StationSearchView: View {
    @EnvironmentObject var store: StationsStore
    @EnvironmentObject var player: RadioPlayer
    @StateObject private var service = RadioBrowserService()
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedCountry: CountryFilter = .all
    @State private var addedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                Divider()
                resultsList
            }
            .navigationTitle(String(localized: "search.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "action.close")) { dismiss() }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: String(localized: "search.placeholder"))
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: query) { _, new in
                if new.isEmpty { service.loadTopStations(countryCode: selectedCountry.code) }
                else { runSearch() }
            }
            .onChange(of: selectedCountry) { _, _ in runSearch() }
            .onAppear { service.loadTopStations(countryCode: selectedCountry.code) }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CountryFilter.allCases) { country in
                    FilterChip(
                        label: country.label,
                        isSelected: selectedCountry == country
                    ) {
                        selectedCountry = country
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if service.isLoading {
            Spacer()
            ProgressView()
            Spacer()
        } else if let err = service.error {
            errorView(err)
        } else if service.results.isEmpty && !query.isEmpty {
            emptyView
        } else {
            List(service.results) { station in
                RadioBrowserRow(
                    station: station,
                    isAdded: addedIDs.contains(station.id) || store.stations.contains { $0.url == station.streamURL }
                ) {
                    addStation(station)
                } onPlay: {
                    player.play(station.toStation())
                }
            }
            .listStyle(.plain)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(localized: "search.noResults"))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(localized: "search.error"))
                .foregroundColor(.secondary)
            Button(String(localized: "action.retry")) { runSearch() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func runSearch() {
        service.search(query: query, countryCode: selectedCountry.code)
    }

    private func addStation(_ rb: RadioBrowserStation) {
        store.add(rb.toStation())
        addedIDs.insert(rb.id)
    }
}

// MARK: - Row

struct RadioBrowserRow: View {
    let station: RadioBrowserStation
    let isAdded: Bool
    let onAdd: () -> Void
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Logo
            Group {
                if let raw = station.favicon, let url = URL(string: raw) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                        else { initialsView }
                    }
                } else {
                    initialsView
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(station.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(station.flagEmoji)
                    if let country = station.country, !country.isEmpty {
                        Text(country)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if let br = station.bitrate, br > 0 {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("\(br) kbps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 4) {
                Button {
                    onPlay()
                } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Button {
                    onAdd()
                } label: {
                    Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 22))
                        .foregroundColor(isAdded ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(isAdded)
            }
        }
        .padding(.vertical, 4)
    }

    private var initialsView: some View {
        let colors: [Color] = [.red, .orange, .blue, .purple, .green, .pink, .indigo, .teal]
        let color = colors[abs(station.name.hashValue) % colors.count]
        return ZStack {
            color.opacity(0.18)
            Text(String(station.name.prefix(2)).uppercased())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
    }
}

// MARK: - Filter chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Country filter

enum CountryFilter: String, CaseIterable, Identifiable {
    case all, es, gb, us, fr, de, it, pt, mx, ar

    var id: String { rawValue }

    var code: String? {
        self == .all ? nil : rawValue.uppercased()
    }

    var label: String {
        switch self {
        case .all: return String(localized: "filter.all")
        case .es:  return "🇪🇸 España"
        case .gb:  return "🇬🇧 UK"
        case .us:  return "🇺🇸 USA"
        case .fr:  return "🇫🇷 France"
        case .de:  return "🇩🇪 Germany"
        case .it:  return "🇮🇹 Italy"
        case .pt:  return "🇵🇹 Portugal"
        case .mx:  return "🇲🇽 México"
        case .ar:  return "🇦🇷 Argentina"
        }
    }
}
