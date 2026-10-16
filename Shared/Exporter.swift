import Foundation

/// .md і .csv у Documents (Files → На iPhone → Підходи).
enum Exporter {
    static func write(_ r: WorkoutRecord) -> URL? {
        guard !r.sets.isEmpty else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        let stamp = f.string(from: r.date)

        var md = "# \(r.dayTitle) — \(stamp)\n\n"
        var csv = "date,exercise,weight,set,reps\n"
        for name in r.exerciseNames {
            let sets = r.sets.filter { $0.exercise == name }
            md += "## \(name)\n"
            for (i, l) in sets.enumerated() {
                md += "- Підхід \(i + 1): \(W.label(l.weight)) × \(l.reps)\n"
                csv += "\(stamp),\"\(name)\",\"\(l.weight)\",\(i + 1),\(l.reps)\n"
            }
            md += "\n"
        }
        let mdURL = docs.appendingPathComponent("Тренування-\(stamp).md")
        let csvURL = docs.appendingPathComponent("Тренування-\(stamp).csv")
        try? csv.write(to: csvURL, atomically: true, encoding: .utf8)
        do { try md.write(to: mdURL, atomically: true, encoding: .utf8); return mdURL } catch { return nil }
    }
}
