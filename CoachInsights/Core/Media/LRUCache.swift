import Foundation

struct LRUCache<Key: Hashable, Value> {
    private struct Entry { let value: Value; let cost: Int; var access: UInt64 }
    private var entries: [Key: Entry] = [:]
    private var tick: UInt64 = 0
    private(set) var totalCost = 0
    let costLimit: Int
    var count: Int { entries.count }

    init(costLimit: Int) { self.costLimit = max(costLimit, 0) }
    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        tick &+= 1; entry.access = tick; entries[key] = entry
        return entry.value
    }
    mutating func insert(_ value: Value, for key: Key, cost: Int) {
        if let old = entries.removeValue(forKey: key) { totalCost -= old.cost }
        guard cost >= 0, cost <= costLimit else { return }
        tick &+= 1
        entries[key] = Entry(value: value, cost: cost, access: tick)
        totalCost += cost
        while totalCost > costLimit, let oldest = entries.min(by: { $0.value.access < $1.value.access }) {
            totalCost -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
    }
    mutating func removeAll() { entries.removeAll(); totalCost = 0 }
}
