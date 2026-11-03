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

@Suite struct SudoTests {
    @Test func touchIDAttemptLeavesAskpassOutBecauseItDisablesPamTid() {
        #expect(SudoStep.touchID.arguments == ["-v"])
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
