import Foundation

public struct Request: Equatable {
    public let message: String?
    public let command: [String]
}

public struct UsageError: Error, CustomStringConvertible {
    public let description = "usage: letmedo [-m message] <command> [args...]\n       letmedo --skill"
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
        case .touchID: ["-S", "-v"]
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
        case "'": out += #"\'"#
        case "\\": out += #"\\"#
        default:
            if isHidden(s) { out += escaped(s) } else { out.unicodeScalars.append(s) }
        }
    }
    return out + "'"
}

private func escaped(_ s: Unicode.Scalar) -> String {
    switch s {
    case "\n": #"\n"#
    case "\t": #"\t"#
    case "\r": #"\r"#
    default:
        if s.value < 0x80 { String(format: #"\x%02X"#, s.value) }
        else if s.value <= 0xFFFF { String(format: #"\u%04X"#, s.value) }
        else { String(format: #"\U%08X"#, s.value) }
    }
}

public enum Severity: Sendable { case critical, caution }

public enum Rule: CaseIterable, Sendable {
    case recursiveDelete, shellString, systemPath

    public var severity: Severity { self == .recursiveDelete ? .critical : .caution }
}

public enum Role { case command, flag, path, value, space, escape }

public struct Token: Equatable {
    public let text: String
    public let role: Role
    public let rule: Rule?
}

public struct Argument: Equatable {
    public let index: Int
    public let lines: [[Token]]
}

private let shells: Set = ["sh", "bash", "zsh", "dash", "ksh"]
private let systemDirs = ["/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/private", "/var"]

private func basename(_ path: Substring) -> Substring { path.split(separator: "/").last ?? path }

private func isRecursiveFlag(_ word: Substring) -> Bool {
    word == "--recursive" || (word.hasPrefix("-") && !word.hasPrefix("--") && word.contains { $0 == "r" || $0 == "R" })
}

private func isShellStringFlag(_ word: Substring) -> Bool {
    word.hasPrefix("-") && !word.hasPrefix("--") && word.contains("c")
}

private func isSystemPath(_ word: Substring) -> Bool {
    let path = word.drop { $0 == "'" || $0 == "\"" }
    if path == "/usr/local" || path.hasPrefix("/usr/local/") { return false }
    return systemDirs.contains { path == $0 || path.hasPrefix($0 + "/") }
}

private func role(of word: Substring) -> Role {
    if word.count > 1 && word.hasPrefix("-") { return .flag }
    if ["/", "~", "./", "../"].contains(where: { word.hasPrefix($0) }) { return .path }
    return .value
}

private func rule(of word: Substring, at index: Int, in words: [Substring]) -> Rule? {
    let command = basename(words[0])
    let isRm = command == "rm" && words.dropFirst().contains(where: isRecursiveFlag)
    if index == 0 { return isRm ? .recursiveDelete : nil }
    if isRm && isRecursiveFlag(word) { return .recursiveDelete }
    if shells.contains(String(command)) && isShellStringFlag(word) && index == words.firstIndex(where: isShellStringFlag) {
        return .shellString
    }
    return isSystemPath(word) ? .systemPath : nil
}

public func describe(_ argv: [String]) -> [Argument] {
    let words = argv.map { Substring($0) }
    let scriptIndex = shells.contains(String(basename(words[0])))
        ? words.dropFirst().firstIndex(where: isShellStringFlag).map { $0 + 1 } : nil
    return argv.indices.map { i in
        if i == scriptIndex {
            let lines = argv[i].unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
            return Argument(index: i, lines: lines.map { describeLine(String(String.UnicodeScalarView($0))) })
        }
        let r = rule(of: words[i], at: i, in: words)
        return Argument(index: i, lines: [[Token(text: displayArgument(argv[i]), role: i == 0 ? .command : role(of: words[i]), rule: r)]])
    }
}

private func describeLine(_ line: String) -> [Token] {
    var runs: [Substring] = []
    var start = line.startIndex
    for i in line.indices.dropFirst() where (line[i] == " ") != (line[line.index(before: i)] == " ") {
        runs.append(line[start..<i])
        start = i
    }
    if start < line.endIndex { runs.append(line[start...]) }
    let words = runs.filter { $0.first != " " }
    var wordIndex = 0
    return runs.flatMap { run -> [Token] in
        if run.first == " " { return [Token(text: String(run), role: .space, rule: nil)] }
        defer { wordIndex += 1 }
        let r = rule(of: run, at: wordIndex, in: words)
        let base = wordIndex == 0 ? Role.command : role(of: run)
        var tokens: [Token] = []
        var pending = ""
        for s in run.unicodeScalars {
            if isHidden(s) {
                if !pending.isEmpty { tokens.append(Token(text: pending, role: base, rule: r)); pending = "" }
                tokens.append(Token(text: escaped(s), role: .escape, rule: r))
            } else {
                pending.unicodeScalars.append(s)
            }
        }
        if !pending.isEmpty { tokens.append(Token(text: pending, role: base, rule: r)) }
        return tokens
    }
}

public func rules(_ arguments: [Argument]) -> [Rule] {
    let found = Set(arguments.flatMap { $0.lines.flatMap { $0.compactMap(\.rule) } })
    return Rule.allCases.filter(found.contains)
}

public struct Ticket: Equatable, Comparable {
    public let time: UInt64
    public let pid: Int32
    public let done: Bool

    public init(time: UInt64, pid: Int32, done: Bool = false) {
        self.time = time
        self.pid = pid
        self.done = done
    }

    public init?(name: String) {
        let done = name.hasSuffix(".done")
        let parts = name.dropLast(done ? 5 : 0).split(separator: "-")
        guard parts.count == 2, let time = UInt64(parts[0]), let pid = Int32(parts[1]) else { return nil }
        self.init(time: time, pid: pid, done: done)
    }

    public var name: String { String(format: "%020llu-%d", time, pid) }
    public var doneName: String { name + ".done" }

    public static func < (a: Ticket, b: Ticket) -> Bool { (a.time, a.pid) < (b.time, b.pid) }
}

public struct QueuePosition: Equatable {
    public let ahead: Int
    public let number: Int
    public let total: Int
}

private func isWaiting(_ ticket: Ticket, _ isAlive: (Int32) -> Bool) -> Bool { !ticket.done && isAlive(ticket.pid) }

public func queuePosition(of me: Ticket, among tickets: [Ticket], isAlive: (Int32) -> Bool) -> QueuePosition {
    let older = tickets.filter { $0 < me }
    return QueuePosition(
        ahead: older.filter { isWaiting($0, isAlive) }.count,
        number: older.count + 1,
        total: tickets.count)
}

public func isNewBatch(for me: Ticket, among tickets: [Ticket], isAlive: (Int32) -> Bool) -> Bool {
    !tickets.contains { $0 != me && isWaiting($0, isAlive) }
}
