import SwiftUI
import ShazamKit

struct ShazamButton: View {
    @ObservedObject var shazam: ShazamService
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var player: RadioPlayer
    @State private var showResult = false

    var body: some View {
        Button {
            switch shazam.state {
            case .idle, .noMatch, .error, .found:
                shazam.identify()
            case .listening:
                shazam.cancel()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.pulse, isActive: isListening)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(isListening ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isListening ? Color.accentColor : Color(.secondarySystemFill))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onChange(of: resultAvailable) { _, available in
            if available { showResult = true }
        }
        .onChange(of: shazamFoundItem) { _, item in
            if let item, let station = player.currentStation {
                history.addFromShazam(item, station: station)
            }
        }
        .sheet(isPresented: $showResult, onDismiss: { shazam.cancel() }) {
            ShazamResultView(shazam: shazam)
                .presentationDetents([.medium])
        }
    }

    private var shazamFoundItem: SHMatchedMediaItem? {
        if case .found(let item) = shazam.state { return item }
        return nil
    }

    private var isListening: Bool {
        if case .listening = shazam.state { return true }
        return false
    }

    private var resultAvailable: Bool {
        switch shazam.state {
        case .found, .noMatch, .error: return true
        default: return false
        }
    }

    private var iconName: String {
        switch shazam.state {
        case .listening: return "waveform"
        case .found:     return "checkmark"
        case .noMatch:   return "questionmark"
        case .error:     return "xmark"
        default:         return "shazam.logo"
        }
    }

    private var label: String {
        switch shazam.state {
        case .listening: return "Escuchando..."
        case .found:     return "Identificado"
        case .noMatch:   return "No encontrado"
        case .error:     return "Error"
        default:         return "Identificar"
        }
    }
}

// MARK: - Result sheet

struct ShazamResultView: View {
    @ObservedObject var shazam: ShazamService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch shazam.state {
                case .found(let item):
                    FoundView(item: item)
                case .noMatch:
                    VStack(spacing: 16) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 52))
                            .foregroundColor(.secondary)
                        Text("No se ha podido identificar la canción")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                case .error(let msg):
                    Text(msg).foregroundColor(.secondary).padding()
                default:
                    ProgressView("Identificando...")
                }
            }
            .navigationTitle("Shazam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

private struct FoundView: View {
    let item: SHMatchedMediaItem

    var body: some View {
        VStack(spacing: 20) {
            if let artURL = item.artworkURL {
                AsyncImage(url: artURL) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFit()
                    } else {
                        Color(.secondarySystemFill)
                    }
                }
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 8)
            }

            VStack(spacing: 6) {
                Text(item.title ?? "—")
                    .font(.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(item.artist ?? "—")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let appleURL = item.appleMusicURL {
                Link(destination: appleURL) {
                    Label("Abrir en Apple Music", systemImage: "music.note")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.pink.opacity(0.15))
                        .foregroundColor(.pink)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
    }
}
