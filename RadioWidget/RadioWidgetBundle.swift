import WidgetKit
import SwiftUI

@main
struct RadioWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        QuickStationsWidget()
    }
}
