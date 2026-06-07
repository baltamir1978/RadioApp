import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: StationsStore
    @EnvironmentObject var player: RadioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var showAddStation = false
    @State private var editingStation: Station?

    var body: some View {
        NavigationStack {
            List {
                // MARK: Stations
                Section(String(localized: "settings.stations")) {
                    ForEach(store.stations) { station in
                        HStack {
                            StationLogoView(station: station, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(station.name)
                                    .font(.subheadline)
                                Text(station.url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingStation = station }
                    }
                    .onDelete { store.delete(at: $0) }
                    .onMove  { store.move(from: $0, to: $1) }

                    Button {
                        showAddStation = true
                    } label: {
                        Label(String(localized: "settings.addStation"), systemImage: "plus.circle.fill")
                    }
                }

                // MARK: Buffer
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(localized: "settings.buffer"))
                            Spacer()
                            Text("\(Int(player.bufferDuration)) s")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $player.bufferDuration, in: 2...60, step: 1)
                        HStack {
                            Text(String(localized: "settings.bufferFast"))
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(String(localized: "settings.bufferStable"))
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text(String(localized: "settings.bufferFooter"))
                }
            }
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "action.close")) { dismiss() }
                }
            }
            .sheet(isPresented: $showAddStation) {
                StationFormView(mode: .add)
            }
            .sheet(item: $editingStation) { station in
                StationFormView(mode: .edit(station))
            }
        }
    }
}

// MARK: - Add / Edit form

struct StationFormView: View {
    enum Mode { case add; case edit(Station) }

    @EnvironmentObject var store: StationsStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name    = ""
    @State private var url     = ""
    @State private var logoURL = ""

    private var title: String {
        if case .add = mode { return String(localized: "form.newStation") }
        return String(localized: "form.editStation")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        URL(string: url.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "form.name")) {
                    TextField(String(localized: "form.namePlaceholder"), text: $name)
                        .autocorrectionDisabled()
                }
                Section(String(localized: "form.url")) {
                    TextField(String(localized: "form.urlPlaceholder"), text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
                Section {
                    HStack(spacing: 14) {
                        StationLogoView(
                            station: Station(name: name.isEmpty ? "?" : name, url: "", logoURL: logoURL.isEmpty ? nil : logoURL),
                            size: 40
                        )
                        TextField(String(localized: "form.logoPlaceholder"), text: $logoURL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                    }
                } header: {
                    Text(String(localized: "form.logo"))
                } footer: {
                    Text(String(localized: "form.logoFooter"))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "action.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "action.save")) { save(); dismiss() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if case .edit(let s) = mode {
                    name    = s.name
                    url     = s.url
                    logoURL = s.logoURL ?? ""
                }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let u = url.trimmingCharacters(in: .whitespaces)
        let l = logoURL.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .add:
            store.add(Station(name: n, url: u, logoURL: l.isEmpty ? nil : l))
        case .edit(let existing):
            var s = existing; s.name = n; s.url = u; s.logoURL = l.isEmpty ? nil : l
            store.update(s)
        }
    }
}
