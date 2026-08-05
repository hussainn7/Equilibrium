import Foundation

// Correlations engine: compare avg recovery on days WITH vs WITHOUT each factor
public enum JournalEngine {
    public static func insights(
        entries: [String: JournalEntry],
        recoveryByDay: [String: Int]
    ) -> [FactorInsight] {
        var results: [FactorInsight] = []
        for factor in JournalFactor.allCases {
            var withScores: [Int] = []
            var withoutScores: [Int] = []
            
            for (date, score) in recoveryByDay {
                if let entry = entries[date], entry.factors.contains(factor) {
                    withScores.append(score)
                } else {
                    withoutScores.append(score)
                }
            }
            
            if !withScores.isEmpty && !withoutScores.isEmpty {
                let avgWith = Double(withScores.reduce(0, +)) / Double(withScores.count)
                let avgWithout = Double(withoutScores.reduce(0, +)) / Double(withoutScores.count)
                results.append(FactorInsight(factor: factor, avgWith: avgWith, avgWithout: avgWithout))
            }
        }
        return results.sorted { $0.delta < $1.delta }
    }
}
