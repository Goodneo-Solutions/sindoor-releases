// Built where sMap's SMap module exists (iOS, or any platform with sMap from source).
#if canImport(SMap)
import SwiftUI

/// The navigator's step list in SwiftUI: one row per step (its text, its level when the route changes level), updated
/// as the navigator shows routes.
@available(iOS 15.0, macOS 12.0, *)
public struct SindoorStepsView: View {
    @ObservedObject var navigator: SindoorNavigator
    let showLevels: Bool

    public init(navigator: SindoorNavigator, showLevels: Bool = true) {
        self.navigator = navigator
        self.showLevels = showLevels
    }

    private var multiLevel: Bool { Set(navigator.lines.compactMap(\.level)).count > 1 }

    public var body: some View {
        List(navigator.lines) { line in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(line.id + 1).").foregroundColor(.secondary).monospacedDigit()
                Text(line.text)
                Spacer(minLength: 0)
                if showLevels, multiLevel, let l = line.level {
                    Text("\(navigator.options.text["level"] ?? "Level") \(l)").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.plain)
    }
}
#endif
