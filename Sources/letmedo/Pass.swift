import AppKit
import LetmedoCore
import SwiftUI

enum Palette {
    static let ink = Color(red: 0.949, green: 0.957, blue: 0.973)
    static let soft = Color(red: 0.788, green: 0.808, blue: 0.847)
    static let muted = Color(red: 0.639, green: 0.663, blue: 0.710)
    static let critical = Color(red: 1, green: 0.302, blue: 0.369)
    static let caution = Color(red: 1, green: 0.690, blue: 0)
    static let flag = Color(red: 0.612, green: 0.769, blue: 1)
    static let path = Color(red: 0.902, green: 0.827, blue: 0.639)
    static let escape = Color(red: 0.851, green: 0.627, blue: 1)
    static let plate = Color(red: 0.306, green: 0.310, blue: 0.235).opacity(0.5)
    static let fill = Color(red: 0.192, green: 0.2, blue: 0.043)
    static let stroke = Color(red: 0.298, green: 0.310, blue: 0.063).opacity(0.5)

    static func color(_ rule: Rule) -> Color { rule.severity == .critical ? critical : caution }
}

extension Color {
    var pressed: some ShapeStyle {
        shadow(.inner(color: .black.opacity(0.8), radius: 0.3, y: 0.5)).shadow(.drop(color: .white.opacity(0.3), radius: 0.5, y: -0.5))
    }
}

@MainActor enum Grain {
    static let image: Image = {
        let size = 128
        let pixels = Data((0..<size * size).map { _ in UInt8.random(in: 0...255) })
        let cg = CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: CGDataProvider(data: pixels as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return Image(decorative: cg, scale: 2)
    }()
}

extension Rule {
    var title: String {
        switch self {
        case .recursiveDelete: "Recursive delete"
        case .shellString: "Shell string"
        case .systemPath: "System path"
        }
    }
}

final class Panel: NSPanel {
    var acceptsKey = true
    override var canBecomeKey: Bool { acceptsKey }
}

let cardMargin: CGFloat = 40
let stackPeek: CGFloat = 24
let exitDistance: CGFloat = 48

extension View {
    func card() -> some View {
        background {
            RoundedRectangle(cornerRadius: 32).fill(Palette.fill)
                .overlay(Grain.image.resizable(resizingMode: .tile).opacity(0.08).blendMode(.screen))
                .clipShape(.rect(cornerRadius: 32))
        }
            .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(Palette.stroke))
            .shadow(color: .black.opacity(0.38), radius: 32, y: 12)
    }
}

@MainActor
func makePanel(_ root: some View) -> Panel {
    let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    let hosting = NSHostingView(rootView: root.padding(.horizontal, cardMargin).padding(.vertical, cardMargin + exitDistance).environment(\.colorScheme, .dark))
    panel.contentView = hosting
    hosting.setFrameSize(NSSize(width: 640 + cardMargin * 2, height: 10))
    hosting.layoutSubtreeIfNeeded()
    panel.setContentSize(hosting.fittingSize)
    panel.appearance = NSAppearance(named: .darkAqua)
    return panel
}

@MainActor final class PassState: ObservableObject {
    @Published var position: QueuePosition
    @Published var litRules = 0
    @Published var unlocked = false
    @Published var shown = false
    @Published var exitOffset: CGFloat?
    @Published var authenticating = false

    init(position: QueuePosition) { self.position = position }

    var waiting: Bool { position.ahead > 0 }
}

struct ConfirmView: View {
    let executable: String
    let arguments: [Argument]
    let rules: [Rule]
    let message: String?
    let requester: String
    let requesterPID: Int32
    let cwd: String
    let requestedAt: Date
    let tilt: Double
    @ObservedObject var state: PassState
    let done: (Bool) -> Void

    private func lit(_ rule: Rule) -> Bool {
        (rules.firstIndex(of: rule) ?? .max) < state.litRules
    }

    private func line(_ tokens: [Token]) -> AttributedString {
        tokens.reduce(into: AttributedString()) { out, token in
            var run = AttributedString(token.text)
            switch token.role {
            case .command: run.foregroundColor = Palette.ink; run.font = .system(size: 14, weight: .semibold, design: .monospaced)
            case .flag: run.foregroundColor = Palette.flag
            case .path: run.foregroundColor = Palette.path
            case .escape: run.foregroundColor = Palette.escape; run.backgroundColor = Palette.escape.opacity(0.18)
            case .value, .space: run.foregroundColor = Palette.soft
            }
            if let rule = token.rule, lit(rule), token.role != .space {
                if rule.severity == .critical {
                    run.foregroundColor = .white
                    run.backgroundColor = Palette.critical.opacity(0.4)
                    run.underlineStyle = .single
                } else {
                    run.foregroundColor = Palette.caution
                    run.underlineStyle = Text.LineStyle(pattern: .dash, color: Palette.caution)
                }
            }
            out += run
        }
    }

    private var argv: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(arguments.dropFirst(), id: \.index) { argument in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("$\(argument.index)").foregroundStyle(Palette.muted).font(.system(size: 11, design: .monospaced))
                        .frame(width: 22, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(argument.lines.enumerated()), id: \.offset) { n, tokens in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if argument.lines.count > 1 {
                                    Text("\(n + 1)").foregroundStyle(Palette.muted).font(.system(size: 11, design: .monospaced))
                                        .frame(width: 18, alignment: .trailing)
                                }
                                Text(line(tokens)).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .font(.system(size: 14, design: .monospaced))
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lineCount: Int { arguments.dropFirst().reduce(0) { $0 + $1.lines.count } }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Palette.muted.pressed)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.soft.pressed)
                .lineLimit(4).truncationMode(.middle).textSelection(.enabled)
        }
    }

    private func stamp(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: requestedAt).uppercased()
    }

    private var time: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TIME").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Palette.muted.pressed)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(stamp("HH:mm")).font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundStyle(Palette.ink.pressed)
                Text(stamp(":ss")).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.muted.pressed)
            }
            Rectangle().fill(Palette.muted.opacity(0.35)).frame(height: 1)
            Text(stamp("EEE dd MMM yyyy")).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4).foregroundStyle(Palette.soft.pressed)
        }
        .fixedSize()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("RUN AS ROOT").font(.system(size: 13, weight: .bold)).tracking(1.6).foregroundStyle(Palette.ink.pressed)
                    Spacer()
                    if state.authenticating {
                        Text("AUTHENTICATING").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.caution.pressed)
                    } else if state.waiting {
                        Text("WAITING").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.muted.pressed)
                    }
                }
                Text((executable as NSString).lastPathComponent)
                    .font(.system(size: 40, weight: .bold, design: .monospaced)).foregroundStyle(Palette.ink.pressed)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .padding(.top, 10)
                Text(executable).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted.pressed)
                    .textSelection(.enabled)
                if arguments.count > 1 {
                    Group {
                        if lineCount > 14 {
                            ScrollView { argv.padding(14) }.frame(height: 320)
                        } else {
                            argv.padding(14)
                        }
                    }
                    .background(Palette.plate, in: .rect(cornerRadius: 14))
                    .padding(.top, 16)
                }
                HStack(spacing: 8) {
                    if rules.isEmpty {
                        Text("No rule matched").font(.system(size: 12)).foregroundStyle(Palette.muted.pressed)
                    }
                    ForEach(rules, id: \.self) { rule in
                        Text(rule.title).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(lit(rule) ? Palette.color(rule) : Palette.muted)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Palette.color(rule).opacity(lit(rule) ? 0.18 : 0.06), in: .capsule)
                            .overlay(Capsule().strokeBorder(Palette.color(rule).opacity(lit(rule) ? 0.8 : 0.2),
                                style: StrokeStyle(lineWidth: 1, dash: rule.severity == .critical ? [] : [3, 2])))
                    }
                }
                .padding(.top, 12)
                if let message {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AGENT CLAIMS").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.muted.pressed)
                        Text(message).font(.system(size: 15)).foregroundStyle(Palette.soft.pressed)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .padding(.top, 18)
                }
                HStack(spacing: 10) {
                    Button("Cancel") { done(false) }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.bordered)
                    Button("Run") { done(true) }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.critical)
                        .disabled(!state.unlocked)
                }
                .controlSize(.large)
                .disabled(state.waiting || state.authenticating)
                .padding(.top, 22)
            }
            .padding(24)
            .frame(width: 490, alignment: .leading)

            Line().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                .foregroundStyle(.white.opacity(0.17))
                .frame(width: 1.5)
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 14) {
                Text("\(state.position.number) / \(state.position.total)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced)).foregroundStyle(Palette.ink.pressed)
                time
                field("REQUESTER", requester)
                field("DIRECTORY", cwd)
                Spacer(minLength: 12)
                field("PID", "\(requesterPID)")
            }
            .padding(.vertical, 24).padding(.horizontal, 16)
            .frame(width: 148, alignment: .leading)
        }
        .frame(width: 640)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(state.waiting ? 0.45 : 1)
        .card()
        .rotationEffect(.degrees(state.waiting ? tilt : 0))
        .offset(y: state.exitOffset ?? -stackPeek * CGFloat(min(state.position.ahead, 3)))
        .opacity(state.exitOffset == nil ? 1 : 0)
        .scaleEffect(state.shown ? 1 : 0.94)
        .opacity(state.shown ? 1 : 0)
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: rect.midX, y: rect.minY)); $0.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) }
    }
}

final class Field { var text = "" }

struct PasswordView: View {
    let prompt: String
    let done: (String?) -> Void
    private let field = Field()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TOUCH ID UNAVAILABLE").font(.system(size: 13, weight: .bold)).tracking(1.6).foregroundStyle(Palette.ink.pressed)
            Text("Enter password").font(.system(size: 28, weight: .bold)).foregroundStyle(Palette.ink.pressed).padding(.top, 6)
            Text(prompt).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted.pressed).padding(.top, 6)
            SecureField("Password", text: Binding(get: { field.text }, set: { field.text = $0 }))
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .onSubmit { done(field.text) }
                .padding(.top, 18)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { done(nil) }.keyboardShortcut(.cancelAction).buttonStyle(.bordered)
                Button("Submit") { done(field.text) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.top, 20)
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .card()
    }
}
