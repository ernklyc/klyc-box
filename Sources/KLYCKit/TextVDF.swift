import Foundation

/// Valve's text key-value format (appmanifest, localconfig, loginusers): `"key" "value"` pairs and `"key" { … }` blocks.
public struct VDFNode: Sendable {
    public var key: String
    public var value: String?
    public var children: [VDFNode]

    public subscript(_ name: String) -> VDFNode? { children.first { $0.key.caseInsensitiveCompare(name) == .orderedSame } }
    public func string(_ name: String) -> String? { self[name]?.value }
    public func int(_ name: String) -> Int? { string(name).flatMap { Int($0) } }
}

public enum TextVDF {
    /// A tolerant parse: a broken or truncated file gives what could be read, never a crash.
    public static func parse(_ text: String) -> VDFNode {
        var scanner = Scanner(Array(text.unicodeScalars))
        var root = VDFNode(key: "", value: nil, children: [])
        scanner.block(into: &root, top: true)
        return root
    }

    private struct Scanner {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        enum Token { case string(String), open, close, end }

        mutating func next() -> Token {
            while i < s.count {
                let c = s[i]
                if c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{FEFF}" { i += 1; continue }
                if c == "/", i + 1 < s.count, s[i + 1] == "/" { while i < s.count, s[i] != "\n" { i += 1 }; continue }   // comment
                if c == "{" { i += 1; return .open }
                if c == "}" { i += 1; return .close }
                if c == "\"" {
                    i += 1
                    var out = String.UnicodeScalarView()
                    while i < s.count, s[i] != "\"" {
                        if s[i] == "\\", i + 1 < s.count {
                            i += 1
                            switch s[i] { case "n": out.append("\n"); case "t": out.append("\t"); default: out.append(s[i]) }
                        } else { out.append(s[i]) }
                        i += 1
                    }
                    i += 1
                    return .string(String(out))
                }
                // an unquoted word
                var out = String.UnicodeScalarView()
                while i < s.count, !" \t\r\n{}\"".unicodeScalars.contains(s[i]) { out.append(s[i]); i += 1 }
                return .string(String(out))
            }
            return .end
        }

        mutating func block(into node: inout VDFNode, top: Bool) {
            while true {
                switch next() {
                case .end: return
                case .close: if !top { return }
                case .open: continue
                case .string(let key):
                    switch next() {
                    case .string(let value): node.children.append(VDFNode(key: key, value: value, children: []))
                    case .open:
                        var child = VDFNode(key: key, value: nil, children: [])
                        block(into: &child, top: false)
                        node.children.append(child)
                    case .close: if !top { return }
                    case .end: return
                    }
                }
            }
        }
    }
}
