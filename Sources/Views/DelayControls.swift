import SwiftUI

/// Réglage du délai : un **champ éditable** (ms) + des **boutons ± à pas variés**.
/// (Pas de `Slider` : sur macOS un Slider avec `step:` dessine un repère par pas — ici ~1001 —
/// ce qui ralentit tout le rendu. Champ + boutons = précis et instantané.)
struct DelayControls: View {
    @ObservedObject var delay: DelayController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Delay")
                Spacer()
                TextField("", value: msBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .font(.system(.title3, design: .monospaced))
                Text("ms").foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                nudge("-100", -100)
                nudge("-10", -10)
                nudge("-1", -1)
                Spacer()
                nudge("+1", 1)
                nudge("+10", 10)
                nudge("+100", 100)
            }
        }
    }

    /// Valeur entière en ms, bornée à 0…1000 (champ éditable).
    private var msBinding: Binding<Int> {
        Binding(get: { Int(delay.ms.rounded()) },
                set: { delay.ms = min(1000, max(0, Double($0))) })
    }

    private func nudge(_ label: String, _ delta: Double) -> some View {
        Button(label) { delay.nudge(by: delta) }
            .monospacedDigit()
    }
}
