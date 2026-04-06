import Foundation

/// One day's worth of emotion event counts.
/// Uses a [String: Int] dict so it works with any label set from the model.
struct DayRecord: Codable, Identifiable {
    var id: String { dateString }
    var dateString: String
    var counts: [String: Int]

    init(dateString: String) {
        self.dateString = dateString
        self.counts = [:]
    }

    static func dateString(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    /// Total events this day.
    var totalEvents: Int { counts.values.reduce(0, +) }
}

/// Rolling 30-day history of DayRecords, persisted to UserDefaults.
final class DailyLog: ObservableObject {
    @Published private(set) var records: [DayRecord] = []

    private let defaultsKey = "dog_sense_daily_log_v2"
    private let maxDays = 30

    init() { load() }

    var today: DayRecord {
        let key = DayRecord.dateString(for: Date())
        return records.first(where: { $0.dateString == key }) ?? DayRecord(dateString: key)
    }

    func increment(label: String) {
        mutateToday { record in
            record.counts[label, default: 0] += 1
        }
    }

    private func mutateToday(_ transform: (inout DayRecord) -> Void) {
        let key = DayRecord.dateString(for: Date())
        if let idx = records.firstIndex(where: { $0.dateString == key }) {
            transform(&records[idx])
        } else {
            var record = DayRecord(dateString: key)
            transform(&record)
            records.append(record)
            if records.count > maxDays {
                records.removeFirst(records.count - maxDays)
            }
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([DayRecord].self, from: data)
        else { return }
        records = decoded
    }
}
