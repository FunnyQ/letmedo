import Testing
@testable import PkexecCore

@Suite struct DisplayTests {
    @Test func plainArgumentStaysBare() {
        #expect(displayArgument("/usr/bin/id") == "/usr/bin/id")
        #expect(displayArgument("-u") == "-u")
    }

    @Test func spacesAndQuotesAreSingleQuoted() {
        #expect(displayArgument("a b") == "'a b'")
        #expect(displayArgument("it's") == #"'it'\''s'"#)
        #expect(displayArgument("") == "''")
    }

    @Test func invisibleCharactersAreEscapedSoTheyCannotHideText() {
        let bs = String(UnicodeScalar(0x5C))
        #expect(displayArgument("a\nb") == #"$'a\nb'"#)
        #expect(displayArgument("safe\u{202E}fdp.exe") == "$'safe" + bs + "u202Efdp.exe'")
        #expect(displayArgument("\u{1B}[2Kx") == #"$'\x1B[2Kx'"#)
        #expect(displayArgument("zero\u{200B}width") == "$'zero" + bs + "u200Bwidth'")
    }

    @Test func commandJoinsArguments() {
        #expect(displayCommand(["/bin/rm", "-rf", "/tmp/a b"]) == "/bin/rm -rf '/tmp/a b'")
    }
}

@Suite struct RequestTests {
    @Test func parsesMessageAndCommand() throws {
        let r = try parseRequest(["-m", "why", "ls", "-la"])
        #expect(r.message == "why")
        #expect(r.command == ["ls", "-la"])
    }

    @Test func messageIsOptional() throws {
        let r = try parseRequest(["ls"])
        #expect(r.message == nil)
        #expect(r.command == ["ls"])
    }

    @Test func emptyCommandIsRejected() {
        #expect(throws: UsageError.self) { try parseRequest([]) }
        #expect(throws: UsageError.self) { try parseRequest(["-m", "why"]) }
        #expect(throws: UsageError.self) { try parseRequest(["-m"]) }
    }
}

@Suite struct ResolveTests {
    let existing: Set<String> = ["/opt/bin/ls", "/bin/ls", "/usr/sbin/diskutil"]

    @Test func searchesPathInOrder() {
        #expect(resolveExecutable("ls", path: "/opt/bin:/bin", cwd: "/x") { existing.contains($0) } == "/opt/bin/ls")
    }

    @Test func absolutePathIsKept() {
        #expect(resolveExecutable("/usr/sbin/diskutil", path: "", cwd: "/x") { existing.contains($0) } == "/usr/sbin/diskutil")
    }

    @Test func relativePathWithSlashResolvesAgainstCwd() {
        #expect(resolveExecutable("./ls", path: "/bin", cwd: "/opt/bin") { existing.contains($0) } == "/opt/bin/ls")
    }

    @Test func missingCommandResolvesToNil() {
        #expect(resolveExecutable("nope", path: "/bin", cwd: "/x") { existing.contains($0) } == nil)
    }
}

@Suite struct RuleTests {
    @Test func recursiveRmIsCritical() {
        #expect(rules(describe(["/bin/rm", "-rf", "/tmp/x"])) == [.recursiveDelete])
        #expect(rules(describe(["/bin/rm", "-R", "/tmp/x"])) == [.recursiveDelete])
        #expect(rules(describe(["/bin/rm", "--recursive", "/tmp/x"])) == [.recursiveDelete])
        #expect(Rule.recursiveDelete.severity == .critical)
    }

    @Test func plainRmIsNotRecursive() {
        #expect(rules(describe(["/bin/rm", "-f", "/tmp/x"])) == [])
    }

    @Test func shellStringIsCaution() {
        #expect(rules(describe(["/bin/sh", "-c", "echo hi"])) == [.shellString])
        #expect(rules(describe(["/bin/zsh", "-lc", "echo hi"])) == [.shellString])
        #expect(Rule.shellString.severity == .caution)
    }

    @Test func systemPathsAreFlaggedButUsrLocalIsNot() {
        #expect(rules(describe(["/bin/cp", "a", "/Library/x"])) == [.systemPath])
        #expect(rules(describe(["/bin/cp", "a", "/usr/local/x"])) == [])
        #expect(rules(describe(["/bin/cp", "a", "/usrx"])) == [])
    }

    @Test func rulesInsideAShellScriptAreFoundAndOrderedBySeverity() {
        let argv = ["/bin/sh", "-c", "launchctl list\nrm -rf '/Library/Helper'"]
        #expect(rules(describe(argv)) == [.recursiveDelete, .shellString, .systemPath])
    }

    @Test func noMatchMeansNoRules() {
        #expect(rules(describe(["/usr/bin/dscacheutil", "-flushcache"])) == [])
    }
}

@Suite struct DescribeTests {
    @Test func argumentsKeepTheirIndexAndRole() {
        let args = describe(["/bin/cp", "-p", "a b", "/tmp/x"])
        #expect(args.map(\.index) == [0, 1, 2, 3])
        #expect(args.map { $0.lines[0][0].role } == [.command, .flag, .value, .path])
        #expect(args[2].lines[0][0].text == "'a b'")
    }

    @Test func shellScriptSplitsIntoLinesWithTheFirstWordAsCommand() {
        let script = describe(["/bin/sh", "-c", "echo  hi\nrm -rf /x"])[2]
        #expect(script.lines.count == 2)
        #expect(script.lines[0].map(\.text) == ["echo", "  ", "hi"])
        #expect(script.lines[0].map(\.role) == [.command, .space, .value])
        #expect(script.lines[1].map(\.rule) == [.recursiveDelete, nil, .recursiveDelete, nil, nil])
    }

    @Test func hiddenCharactersInAScriptAreEscapedAsTheirOwnToken() {
        let bs = String(UnicodeScalar(0x5C))
        let line = describe(["/bin/sh", "-c", "echo a\u{202E}b\tc"])[2].lines[0]
        #expect(line.map(\.text) == ["echo", " ", "a", bs + "u202E", "b", bs + "t", "c"])
        #expect(line[3].role == .escape)
        #expect(line[5].role == .escape)
    }

    @Test func scriptTextJoinsBackToTheOriginalVisibleCharacters() {
        let lines = describe(["/bin/sh", "-c", "a  b\n\nc"])[2].lines
        #expect(lines.map { $0.map(\.text).joined() } == ["a  b", "", "c"])
    }

    @Test func outsideAShellNewlinesStayEscapedInOneLine() {
        let arg = describe(["/bin/echo", "a\nb"])[1]
        #expect(arg.lines == [[Token(text: #"$'a\nb'"#, role: .value, rule: nil)]])
    }
}

@Suite struct QueueTests {
    let a = Ticket(time: 1, pid: 10)
    let b = Ticket(time: 2, pid: 20)
    let c = Ticket(time: 3, pid: 30)

    @Test func ticketNameRoundTrips() {
        #expect(Ticket(name: b.name) == b)
        #expect(Ticket(name: b.doneName) == Ticket(time: 2, pid: 20, done: true))
        #expect(Ticket(name: "junk") == nil)
    }

    @Test func ticketsSortByTimeSoNamesSortToo() {
        #expect(Ticket(time: 9, pid: 1).name < Ticket(time: 10, pid: 1).name)
    }

    @Test func numberCountsTheWholeBatch() {
        let q = queuePosition(of: c, among: [c, a, b]) { _ in true }
        #expect(q == QueuePosition(ahead: 2, number: 3, total: 3))
    }

    @Test func finishedTicketsKeepTheirPlaceInTheNumberButNotInTheQueue() {
        let done = Ticket(time: 1, pid: 10, done: true)
        let q = queuePosition(of: c, among: [done, b, c]) { _ in true }
        #expect(q == QueuePosition(ahead: 1, number: 3, total: 3))
    }

    @Test func aDeadTicketCountsAsFinished() {
        let q = queuePosition(of: c, among: [a, b, c]) { $0 != 10 }
        #expect(q == QueuePosition(ahead: 1, number: 3, total: 3))
    }

    @Test func aBatchIsOverWhenNoOtherTicketIsWaiting() {
        let done = Ticket(time: 1, pid: 10, done: true)
        #expect(isNewBatch(for: c, among: [done, a, c]) { $0 != 10 })
        #expect(!isNewBatch(for: c, among: [b, c]) { _ in true })
    }
}

@Suite struct SudoTests {
    @Test func touchIDAttemptLeavesAskpassOutBecauseItDisablesPamTid() {
        #expect(!SudoStep.touchID.arguments.contains("-A"))
    }

    @Test func touchIDAttemptReadsAPasswordFromStdinSoACancelCannotWaitOnTheTty() {
        #expect(SudoStep.touchID.arguments == ["-S", "-v"])
    }

    @Test func passwordFallbackUsesAskpass() {
        #expect(SudoStep.password.arguments == ["-A", "-v"])
    }

    @Test func runNeverPrompts() {
        #expect(SudoStep.run(executable: "/bin/ls", arguments: ["-la"]).arguments == ["-n", "--", "/bin/ls", "-la"])
    }

    @Test func resetDropsTheCredential() {
        #expect(SudoStep.reset.arguments == ["-k"])
    }
}

@Suite struct SkillTests {
    @Test func skillIsAnAgentSkillWithFrontmatter() {
        #expect(skill.hasPrefix("---\nname: pkexec\ndescription: "))
        #expect(skill.hasSuffix("\n"))
    }
}
