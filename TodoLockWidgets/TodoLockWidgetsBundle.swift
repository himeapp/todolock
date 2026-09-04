import WidgetKit
import SwiftUI

@main
struct TodoLockWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LockHomeWidget()
        if #available(iOS 16.1, *) {
            LockLiveActivityWidget()
        }
    }
}
