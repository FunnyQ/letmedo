import AppKit
import Darwin
import PkexecCore
import SwiftUI

@MainActor
func present<Result>(_ fallback: Result, _ content: (@escaping (Result) -> Void) -> some View) -> Result {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    var result = fallback
    let panel = NSPanel(
        contentRect: .zero, styleMask: [.titled, .fullSizeContentView],
        backing: .buffered, defer: false)
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    panel.level = .modalPanel
    panel.contentView = NSHostingView(rootView: content { value in
        result = value
        app.stopModal()
    })
    panel.center()
    app.activate()
    app.runModal(for: panel)
    panel.close()
    return result
}

struct ConfirmView: View {
    let command: String
    let message: String?
    let requester: String
    let cwd: String
    let requestedAt: String
    let done: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("以 root 執行").font(.title2.bold())
            Text(command)
                .font(.system(.title3, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: .rect(cornerRadius: 8))
            if let message {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent 聲稱").font(.caption).foregroundStyle(.secondary)
                    Text(message)
                }
            }
            Grid(alignment: .leading) {
                GridRow { Text("請求者").foregroundStyle(.secondary); Text(requester) }
                GridRow { Text("目錄").foregroundStyle(.secondary); Text(cwd) }
                GridRow { Text("時間").foregroundStyle(.secondary); Text(requestedAt) }
            }
            .font(.caption)
            HStack {
                Spacer()
                Button("取消") { done(false) }.keyboardShortcut(.cancelAction)
                Button("執行") { done(true) }
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

struct PasswordView: View {
    let prompt: String
    let done: (String?) -> Void
    private final class Field { var text = "" }
    private let field = Field()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Touch ID 無法使用，請輸入密碼").font(.title3.bold())
            Text(prompt).font(.caption).foregroundStyle(.secondary)
            SecureField("密碼", text: Binding(get: { field.text }, set: { field.text = $0 }))
                .onSubmit { done(field.text) }
            HStack {
                Spacer()
                Button("取消") { done(nil) }.keyboardShortcut(.cancelAction)
                Button("送出") { done(field.text) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

func processPath(_ pid: pid_t) -> String {
    var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return "pid \(pid)" }
    return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
}

let askpassVariable = "PKEXEC_ASKPASS"
let env = ProcessInfo.processInfo.environment

if env[askpassVariable] == "1" {
    let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
    guard let password = MainActor.assumeIsolated({ present(nil) { PasswordView(prompt: prompt, done: $0) } }) else { exit(1) }
    print(password)
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
    FileHandle.standardError.write("pkexec: command not found: \(request.command[0])\n".data(using: .utf8)!)
    exit(127)
}
let arguments = Array(request.command.dropFirst())

let approved = MainActor.assumeIsolated {
    present(false) {
        ConfirmView(
            command: displayCommand([executable] + arguments), message: request.message,
            requester: processPath(getppid()), cwd: cwd,
            requestedAt: Date.now.formatted(date: .abbreviated, time: .standard), done: $0)
    }
}
guard approved else {
    FileHandle.standardError.write("pkexec: cancelled\n".data(using: .utf8)!)
    exit(126)
}

func sudo(_ step: SudoStep, quiet: Bool = false) -> Int32 {
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
    do { try process.run() } catch { return 1 }
    process.waitUntilExit()
    return process.terminationStatus
}

_ = sudo(.reset, quiet: true)
guard sudo(.touchID, quiet: true) == 0 || sudo(.password, quiet: true) == 0 else {
    FileHandle.standardError.write("pkexec: authentication failed\n".data(using: .utf8)!)
    exit(126)
}
let status = sudo(.run(executable: executable, arguments: arguments))
_ = sudo(.reset, quiet: true)
exit(status)
