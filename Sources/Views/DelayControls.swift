import SwiftUI

/// Bloc de réglage du délai (valeur + slider 0–1000 ms + boutons fins ±1/±10 ms).
/// Observe le `DelayController` isolé : seul ce bloc se redessine quand on bouge le slider.
struct DelayControls: View {
    @ObservedObject var delay: DelayController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Delay")
                Spacer()
                Text("\(Int(delay.ms)) ms")
                    .font(.system(.title3, design: .monospaced))
                    .bold()
            }

            // Slider continu 0–1000 ms (réglage grossier + en direct).
            Slider(value: $delay.ms, in: 0...1000, step: 1) {
                Text("Delay")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("1000")
            }

            // Réglage fin : ±1 ms et ±10 ms.
            HStack(spacing: 8) {
                nudge("-10", -10)
                nudge("-1", -1)
                Spacer()
                nudge("+1", 1)
                nudge("+10", 10)
            }
        }
    }

    private func nudge(_ label: String, _ delta: Double) -> some View {
        Button(label) { delay.nudge(by: delta) }
            .monospacedDigit()
    }
}
