import SwiftUI

struct RecoveryDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    if let recovery = model.recovery(for: model.selectedDayKey) {
                        heroCard(recovery)
                        componentsCard(recovery)
                        hrvCard(recovery)
                        rhrCard(recovery)
                    } else {
                        EmptyDataHint(text: "No recovery data for this day.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heroCard(_ recovery: RecoveryResult) -> some View {
        SectionCard {
            VStack(spacing: 12) {
                RingGauge(
                    progress: Double(recovery.score) / 100,
                    color: Theme.recoveryColor(zone: recovery.zone),
                    lineWidth: 18
                ) {
                    VStack(spacing: 2) {
                        Text("\(recovery.score)")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("% Recovery")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 190, height: 190)
                .frame(maxWidth: .infinity)

                Text(zoneText(recovery.zone))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                if recovery.calibrating {
                    PillBadge(text: "Baseline still calibrating", color: Theme.yellow)
                }
            }
        }
    }

    private func zoneText(_ zone: RecoveryZone) -> String {
        switch zone {
        case .green:
            return "Your body is recovered – a good day for intense strain."
        case .yellow:
            return "Moderately recovered. Moderate training is okay, listen to your body."
        case .red:
            return "Your body needs recovery. Better to regenerate today."
        }
    }

    private func componentsCard(_ recovery: RecoveryResult) -> some View {
        SectionCard("Influencing Factors") {
            VStack(spacing: 12) {
                ForEach(recovery.components, id: \.key) { component in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(component.label)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Text("· Weight \(Int((component.weight * 100).rounded())) %")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(component.detail)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.cardElevated)
                                Capsule()
                                    .fill(componentColor(component.score01))
                                    .frame(width: max(4, geo.size.width * CGFloat(component.score01)))
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
    }

    private func componentColor(_ score: Double) -> Color {
        if score >= 0.62 { return Theme.green }
        if score >= 0.38 { return Theme.yellow }
        return Theme.red
    }

    private func hrvCard(_ recovery: RecoveryResult) -> some View {
        SectionCard("HRV – last 30 days") {
            let points = trendPoints(model.trend(30) { $0.hrvRmssd })
            if points.count >= 2 {
                BaselineLineChart(
                    points: points,
                    baseline: recovery.hrvBaseline,
                    color: Theme.teal,
                    isLogBaseline: true
                )
                Text("Band = personal baseline ± 1 SD. Higher than the band is good, below indicates strain.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                EmptyDataHint(text: "Not enough HRV nights yet.")
            }
        }
    }

    private func rhrCard(_ recovery: RecoveryResult) -> some View {
        SectionCard("Resting HR – last 30 days") {
            let points = trendPoints(model.trend(30) { $0.restingHR })
            if points.count >= 2 {
                BaselineLineChart(
                    points: points,
                    baseline: recovery.rhrBaseline,
                    color: Theme.red
                )
                Text("An elevated resting HR compared to the baseline is an early sign of stress, illness, or incomplete recovery.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                EmptyDataHint(text: "Not enough resting HR values yet.")
            }
        }
    }
}
