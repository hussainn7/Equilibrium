import SwiftUI

struct SleepDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    if let sleep = model.sleep(for: model.selectedDayKey), sleep.hasData {
                        heroCard(sleep)
                        statsCard(sleep)
                        if let session = model.selectedRecord?.mainSleep, !session.stages.isEmpty {
                            SectionCard("Sleep Stages") {
                                StagesTimelineView(session: session)
                            }
                            SectionCard("Distribution") {
                                StageDistributionView(stageMinutes: sleep.stageMinutes)
                            }
                        }
                        napsCard
                        trendCard
                    } else {
                        EmptyDataHint(text: "No sleep recorded for this day.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heroCard(_ sleep: SleepAnalysis) -> some View {
        SectionCard {
            HStack(spacing: 20) {
                RingGauge(
                    progress: sleep.performance / 100,
                    color: Theme.sleepPurple,
                    lineWidth: 14
                ) {
                    VStack(spacing: 0) {
                        Text("\(Int(sleep.performance.rounded()))")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("%")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Fmt.hm(sleep.sleptMinutes)) h")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("of \(Fmt.hm(sleep.needMinutes)) h need")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let bed = sleep.bedTime, let wake = sleep.wakeTime {
                        Label("\(Fmt.clock(bed)) – \(Fmt.clock(wake))", systemImage: "moon.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if sleep.napMinutes > 1 {
                        Label("\(Int(sleep.napMinutes.rounded())) min nap", systemImage: "powersleep")
                            .font(.caption)
                            .foregroundStyle(Theme.teal)
                    }
                }
            }
        }
    }

    private func statsCard(_ sleep: SleepAnalysis) -> some View {
        SectionCard("Metrics") {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    StatCell(
                        label: "Sleep Debt",
                        value: "\(Fmt.hm(sleep.debtAfterMinutes)) h",
                        color: sleep.debtAfterMinutes > 60 ? Theme.orange : Theme.textPrimary
                    )
                    StatCell(
                        label: "Efficiency",
                        value: sleep.efficiency.map { "\(Int($0.rounded())) %" } ?? "–"
                    )
                    StatCell(
                        label: "Consistency",
                        value: sleep.consistency.map { "\(Int($0.rounded())) %" } ?? "–"
                    )
                }
                HStack(spacing: 12) {
                    StatCell(
                        label: "Restorative (Deep + REM)",
                        value: "\(Fmt.hm(sleep.restorativeMinutes)) h",
                        color: Theme.sleepPurple
                    )
                    StatCell(
                        label: "Deep Sleep",
                        value: "\(Fmt.hm(sleep.stageMinutes[.deep] ?? 0)) h"
                    )
                    StatCell(
                        label: "REM",
                        value: "\(Fmt.hm(sleep.stageMinutes[.rem] ?? 0)) h"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var napsCard: some View {
        if let record = model.selectedRecord, !record.naps.isEmpty {
            SectionCard("Naps") {
                VStack(spacing: 8) {
                    ForEach(record.naps, id: \.id) { nap in
                        HStack {
                            Image(systemName: "powersleep")
                                .foregroundStyle(Theme.teal)
                            Text("\(Fmt.clock(nap.start)) – \(Fmt.clock(nap.end))")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(Int(nap.minutesAsleep.rounded())) min")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var trendCard: some View {
        SectionCard("Last 14 Nights") {
            let slept = trendPoints(model.trend(14) { record in
                model.sleep(for: record.date)?.hasData == true ? model.sleep(for: record.date)?.sleptMinutes : nil
            })
            let need = trendPoints(model.trend(14) { record in
                model.sleep(for: record.date)?.needMinutes
            })
            if slept.count >= 2 {
                SleepTrendChart(slept: slept, need: need)
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.sleepPurple).frame(width: 10, height: 10)
                        Text("Slept")
                    }
                    HStack(spacing: 5) {
                        Capsule().fill(.white.opacity(0.7)).frame(width: 12, height: 2)
                        Text("Need")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            } else {
                EmptyDataHint(text: "Not enough nights for the trend yet.")
            }
        }
    }
}
