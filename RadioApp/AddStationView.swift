import SwiftUI

struct AddStationView: View {
    @EnvironmentObject var store: StationsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var streamURL = ""
    @State private var logoURL = ""
    @State private var country = ""
    @State private var genre = ""

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

                if !streamURL.isEmpty, URL(string: streamURL) == nil {
                    Section {
                        Label(NSLocalizedString("invalid_url", comment: ""), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("add_station", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("add", comment: "")) {
                        store.add(Station(
                            name: name,
                            streamURL: streamURL,
                            logoURL: logoURL.isEmpty ? nil : logoURL,
                            country: country.isEmpty ? nil : country.uppercased(),
                            genre: genre.isEmpty ? nil : genre
                        ))
                        dismiss()
                    }
                    .disabled(!isValid)
                    .bold()
                }
            }
        }
    }
}
