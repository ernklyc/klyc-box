import Foundation

/// Valve's binary key-value format (the achievement files under Steam's appcache/stats).
public indirect enum BinaryVDF: Sendable, Equatable {
    case object([String: BinaryVDF])
    case string(String)
    case int(Int)

    public subscript(_ key: String) -> BinaryVDF? { if case .object(let d) = self { return d[key] } else { return nil } }
    public var keys: [String] { if case .object(let d) = self { return Array(d.keys) } else { return [] } }
    public var intValue: Int? { if case .int(let n) = self { return n } else { return nil } }
    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }

    /// A tolerant parse: unknown types or a cut-off file end the read, they never crash it.
    public static func parse(_ data: Data) -> BinaryVDF {
        let b = [UInt8](data)
        var i = 0
        func cstring() -> String? {
            guard let end = b[i...].firstIndex(of: 0) else { return nil }
            defer { i = end + 1 }
            return String(decoding: b[i..<end], as: UTF8.self)
        }
        func block() -> [String: BinaryVDF] {
            var out: [String: BinaryVDF] = [:]
            while i < b.count {
                let type = b[i]; i += 1
                if type == 8 { return out }
                guard let key = cstring() else { return out }
                switch type {
                case 0: out[key] = .object(block())
                case 1: guard let s = cstring() else { return out }; out[key] = .string(s)
                case 2, 3: guard i + 4 <= b.count else { return out }
                    let raw = b[i..<i + 4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32(8 * $1.offset) }
                    out[key] = .int(Int(Int32(bitPattern: raw))); i += 4
                case 7, 10: guard i + 8 <= b.count else { return out }
                    let raw = b[i..<i + 8].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << UInt64(8 * $1.offset) }
                    out[key] = .int(Int(truncatingIfNeeded: raw)); i += 8
                default: return out
                }
            }
            return out
        }
        return .object(block())
    }
}
