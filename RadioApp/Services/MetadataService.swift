import AVFoundation
import Combine

final class MetadataService: NSObject, ObservableObject, AVPlayerItemMetadataOutputPushDelegate {
    @Published var streamTitle: String?
    @Published var streamGenre: String?

    /// Emits a stable track title after 3 s without changes — use this to save to history.
    var stableTrackPublisher: AnyPublisher<String, Never> {
        $streamTitle
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .removeDuplicates()
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var cancellables = Set<AnyCancellable>()

    func attach(to item: AVPlayerItem) {
        detach()
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
        metadataOutput = output
    }

    func detach() {
        streamTitle = nil
        streamGenre = nil
        metadataOutput = nil
    }

    // MARK: - AVPlayerItemMetadataOutputPushDelegate

    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        for group in groups {
            for item in group.items {
                switch item.commonKey {
                case .commonKeyTitle:
                    streamTitle = item.value as? String
                case .commonKeyType:
                    streamGenre = item.value as? String
                default:
                    if item.identifier?.rawValue.contains("StreamTitle") == true {
                        streamTitle = item.value as? String
                    }
                }
            }
        }
    }
}
