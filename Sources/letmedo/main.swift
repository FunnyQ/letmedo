import AppKit
import Darwin
import LetmedoCore
import SwiftUI

func processPath(_ pid: pid_t) -> String {
    var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return "pid \(pid)" }
    return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
}

let askpassVariable = "LETMEDO_ASKPASS"
let env = ProcessInfo.processInfo.environment

if env[askpassVariable] == "1" {
    let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
    let password: String? = MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var result: String?
        let panel = makePanel(PasswordView(prompt: prompt) { value in
            result = value
            app.stopModal()
        })
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 2)
        panel.center()
        app.runModal(for: panel)
        panel.close()
        return result
    }
    guard let password else { exit(1) }
    print(password)
    exit(0)
}

if CommandLine.arguments.dropFirst().first == "--skill" {
    print(skill, terminator: "")
    exit(0)
}

let request: Request
do {
    request = try parseRequest(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
    exit(2)
}

let cwd = FileManager.default.currentDirectoryPath
guard let executable = resolveExecutable(
    request.command[0], path: env["PATH"] ?? "", cwd: cwd,
    isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
else {
    FileHandle.standardError.write("letmedo: command not found: \(request.command[0])\n".data(using: .utf8)!)
    exit(127)
}
let arguments = Array(request.command.dropFirst())

let queueDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches/letmedo/queue")
let ticket = Ticket(time: clock_gettime_nsec_np(CLOCK_REALTIME), pid: getpid())
let ticketURL = queueDir.appending(path: ticket.name)
try? FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
FileManager.default.createFile(atPath: ticketURL.path, contents: nil)

func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

@MainActor func readTickets() -> [Ticket] {
    ((try? FileManager.default.contentsOfDirectory(atPath: queueDir.path)) ?? []).compactMap(Ticket.init(name:))
}

@MainActor func clearBatch(except keep: Ticket?) {
    for old in readTickets() where old != keep {
        try? FileManager.default.removeItem(at: queueDir.appending(path: old.done ? old.doneName : old.name))
    }
}

@MainActor func readPosition() -> QueuePosition { queuePosition(of: ticket, among: readTickets(), isAlive: isAlive) }

@MainActor func leaveQueue() {
    try? FileManager.default.moveItem(at: ticketURL, to: queueDir.appending(path: ticket.doneName))
    if isNewBatch(for: ticket, among: readTickets(), isAlive: isAlive) { clearBatch(except: nil) }
}

MainActor.assumeIsolated {
    if isNewBatch(for: ticket, among: readTickets(), isAlive: isAlive) { clearBatch(except: ticket) }
}

let stackTop: CGFloat = 220

func sudoProcess(_ step: SudoStep, quiet: Bool) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    process.arguments = step.arguments
    var sudoEnv = env
    sudoEnv["SUDO_ASKPASS"] = processPath(getpid())
    sudoEnv[askpassVariable] = "1"
    process.environment = sudoEnv
    if quiet {
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
    }
    return process
}

func sudo(_ step: SudoStep, quiet: Bool = false) -> Int32 {
    let process = sudoProcess(step, quiet: quiet)
    do { try process.run() } catch { return 1 }
    process.waitUntilExit()
    return process.terminationStatus
}

enum Outcome { case cancelled, failed, authenticated }

let outcome = MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let argv = describe([executable] + arguments)
    let found = rules(argv)
    let state = PassState(position: readPosition())
    var result = Outcome.cancelled
    var onDone: (Bool) -> Void = { _ in }
    let panel = makePanel(ConfirmView(
        executable: executable, arguments: argv, rules: found, message: request.message,
        requester: processPath(getppid()), requesterPID: getppid(), cwd: cwd,
        requestedAt: .now, tilt: [-3.36, 2.52, -1.96, 3.64][Int(getpid()) % 4], state: state
    ) { onDone($0) })
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    let screen = NSScreen.screens[0].visibleFrame
    panel.setFrameTopLeftPoint(NSPoint(x: screen.midX - panel.frame.width / 2, y: screen.midY + stackTop + cardMargin + exitDistance))

    @MainActor func place() {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue - min(state.position.ahead, 3))
        panel.ignoresMouseEvents = state.waiting
        panel.acceptsKey = !state.waiting
    }

    @MainActor func depart(_ value: Outcome) {
        result = value
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
        withAnimation(.easeIn(duration: reduceMotion ? 0 : 0.24)) { state.exitOffset = value == .authenticated ? -exitDistance : exitDistance }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 260))
            app.stopModal()
        }
    }

    var interrupted = false
    var running: Process?
    @MainActor func authenticate(_ step: SudoStep) async -> Bool {
        guard !interrupted else { return false }
        let process = sudoProcess(step, quiet: true)
        running = process
        let status = await withCheckedContinuation { done in
            process.terminationHandler = { done.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch {
                process.terminationHandler = nil
                done.resume(returning: 1)
            }
        }
        running = nil
        return status == 0 && !interrupted
    }

    var leaving = false
    @MainActor func leave(_ approved: Bool) {
        guard !leaving else { return }
        leaving = true
        guard approved else { return depart(.cancelled) }
        state.authenticating = true
        panel.acceptsKey = false
        Task { @MainActor in
            _ = await authenticate(.reset)
            let ok = await authenticate(.touchID) ? true : await authenticate(.password)
            state.authenticating = false
            depart(ok ? .authenticated : interrupted ? .cancelled : .failed)
        }
    }
    onDone = leave

    @MainActor func reachFront() {
        panel.makeKeyAndOrderFront(nil)
        let step = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 80
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            for n in found.indices {
                try? await Task.sleep(for: .milliseconds(step))
                withAnimation(.spring(duration: 0.3, bounce: 0.4)) { state.litRules = n + 1 }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            state.unlocked = true
        }
    }

    place()
    if state.waiting { panel.orderFrontRegardless() } else { reachFront() }
    Task { @MainActor in
        withAnimation(.spring(duration: 0.45, bounce: 0.35)) { state.shown = true }
    }

    let poll = Task { @MainActor in
        place()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            var position = readPosition()
            guard position != state.position else { continue }
            if position.ahead > 0 {
                try? await Task.sleep(for: .milliseconds(300))
                position = readPosition()
            }
            let wasWaiting = state.waiting
            withAnimation(.spring(duration: 0.39, bounce: 0.66)) { state.position = position }
            place()
            if wasWaiting && !state.waiting { reachFront() }
        }
    }
    let signals = [SIGINT, SIGTERM].map { number in
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler {
            interrupted = true
            running?.terminate()
            if leaving { return }
            leave(false)
        }
        source.resume()
        return source
    }
    @MainActor func pump(until deadline: Date) {
        if let event = app.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) { app.sendEvent(event) }
    }
    app.finishLaunching()
    while state.waiting && !interrupted { pump(until: .now + 0.05) }
    if !interrupted { app.runModal(for: panel) }
    signals.forEach { $0.cancel() }
    if interrupted && result != .authenticated { result = .cancelled }
    poll.cancel()
    panel.close()
    return result
}
leaveQueue()
switch outcome {
case .cancelled:
    FileHandle.standardError.write("letmedo: cancelled\n".data(using: .utf8)!)
    exit(126)
case .failed:
    FileHandle.standardError.write("letmedo: authentication failed\n".data(using: .utf8)!)
    exit(126)
case .authenticated:
    let process = sudoProcess(.run(executable: executable, arguments: arguments), quiet: false)
    do { try process.run() } catch { exit(1) }
    let pid = process.processIdentifier
    let relays = [SIGINT, SIGTERM].map { number in
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { @Sendable in kill(pid, number) }
        source.resume()
        return source
    }
    process.waitUntilExit()
    relays.forEach { $0.cancel() }
    _ = sudo(.reset, quiet: true)
    exit(process.terminationStatus)
}
