import SwiftUI

struct EditStationView: View {
    @EnvironmentObject var store: StationsStore
    @Environment(\.dismiss) private var dismiss

    let station: Station

    @State private var name: String
    @State private var streamURL: String
    @State private var logoURL: String
    @State private var country: String
    @State private var genre: String

    init(station: Station) {
        self.station = station
        _name = State(initialValue: station.name)
        _streamURL = State(initialValue: station.streamURL)
        _logoURL = State(initialValue: station.logoURL ?? "")
        _country = State(initialValue: station.country ?? "")
        _genre = State(initialValue: station.genre ?? "")
    }

    private var isValid: Bool {
        !name.isEmpty && !streamURL.isEmpty && URL(string: streamURL) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("station_info", comment: "")) {
                    TextField(NSLocalizedString("name_required", comment: ""), text: $name)
                    TextField(NSLocalizedString("stream_url_required", comment: ""), text: $streamURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField(NSLocalizedString("logo_url_optional", comment: ""), text: $logoURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section(NSLocalizedString("additional_info", comment: "")) {
                    TextField(NSLocalizedString("country_hint", comment: ""), text: $country)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    TextField(NSLocalizedString("genre_hint", comment: ""), text: $genre)
                }

                // Live preview of logo
                if !name.isEmpty {
                    Section(NSLocalizedString("preview", comment: "")) {
                        HStack(spacing: 12) {
                            StationLogo(station: previewStation, size: 52)
                            Text(name).font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("edit_station", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("save", comment: "")) {
                        store.update(station, with: Station(
                            id: station.id,
                            name: name,
                            streamURL: streamURL,
                            logoURL: logoURL.isEmpty ? nil : logoURL,
                            country: country.isEmpty ? nil : country.uppercased(),
                            genre: genre.isEmpty ? nil : genre,
                            stationuuid: station.stationuuid
                        ))
                        dismiss()
                    }
                    .disabled(!isValid)
                    .bold()
                }
            }
        }
    }

    private var previewStation: Station {
        Station(
            id: station.id,
            name: name,
            streamURL: streamURL,
            logoURL: logoURL.isEmpty ? nil : logoURL,
            country: country.isEmpty ? nil : country,
            genre: genre.isEmpty ? nil : genre
        )
    }
}
