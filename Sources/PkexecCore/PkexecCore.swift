import Foundation

public struct Request: Equatable {
    public let message: String?
    public let command: [String]
}

public struct UsageError: Error, CustomStringConvertible {
    public let description = "usage: pkexec [-m message] <command> [args...]"
}

public func parseRequest(_ argv: [String]) throws -> Request {
    var rest = argv[...]
    var message: String?
    if rest.first == "-m" {
        guard rest.count >= 2 else { throw UsageError() }
        message = rest[rest.startIndex + 1]
        rest = rest.dropFirst(2)
    }
    guard !rest.isEmpty else { throw UsageError() }
    return Request(message: message, command: Array(rest))
}

public func resolveExecutable(_ name: String, path: String, cwd: String, isExecutable: (String) -> Bool) -> String? {
    if name.hasPrefix("/") { return isExecutable(name) ? name : nil }
    if name.contains("/") {
        let full = URL(fileURLWithPath: name, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true)).standardizedFileURL.path
        return isExecutable(full) ? full : nil
    }
    for dir in path.split(separator: ":") where !dir.isEmpty {
        let candidate = "\(dir)/\(name)"
        if isExecutable(candidate) { return candidate }
    }
    return nil
}

public enum SudoStep {
    case touchID
    case password
    case run(executable: String, arguments: [String])
    case reset

    public var arguments: [String] {
        switch self {
        case .touchID: ["-v"]
        case .password: ["-A", "-v"]
        case let .run(executable, arguments): ["-n", "--", executable] + arguments
        case .reset: ["-k"]
        }
    }
}

public func displayCommand(_ argv: [String]) -> String {
    argv.map(displayArgument).joined(separator: " ")
}

public func displayArgument(_ arg: String) -> String {
    if arg.isEmpty { return "''" }
    if arg.unicodeScalars.contains(where: isHidden) { return ansiCQuoted(arg) }
    if arg.unicodeScalars.allSatisfy(isBare) { return arg }
    return "'" + arg.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
}

private func isBare(_ s: Unicode.Scalar) -> Bool {
    s.isASCII && (s.properties.isAlphabetic || s.properties.numericType != nil || "_@%+=:,./-".unicodeScalars.contains(s))
}

private func isHidden(_ s: Unicode.Scalar) -> Bool {
    if s == " " { return false }
    switch s.properties.generalCategory {
    case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator,
         .privateUse, .surrogate, .unassigned:
        return true
    default:
        return false
    }
}

private func ansiCQuoted(_ arg: String) -> String {
    var out = "$'"
    for s in arg.unicodeScalars {
        switch s {
        case "\n": out += #"\n"#
        case "\t": out += #"\t"#
        case "\r": out += #"\r"#
        case "'": out += #"\'"#
        case "\\": out += #"\\"#
        default:
            if !isHidden(s) {
                out.unicodeScalars.append(s)
            } else if s.value < 0x80 {
                out += String(format: #"\x%02X"#, s.value)
            } else if s.value <= 0xFFFF {
                out += String(format: #"\u%04X"#, s.value)
            } else {
                out += String(format: #"\U%08X"#, s.value)
            }
        }
    }
    return out + "'"
}
