import Foundation
import Security
import SwiftUI

enum Phrase {
    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "cc.funnyq.pkexec",
        kSecAttrAccount as String: "anti-phishing-phrase",
    ] }

    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(_ phrase: String) -> OSStatus {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(phrase.utf8)
        q[kSecAttrLabel as String] = "pkexec anti-phishing phrase"
        return SecItemAdd(q as CFDictionary, nil)
    }
}

struct PhraseBadge: View {
    let phrase: String?

    var body: some View {
        Group {
            if let phrase {
                VStack(alignment: .leading, spacing: 4) {
                    Text("你的防偽密語").font(.caption).foregroundStyle(.secondary)
                    Text(phrase).font(.title3.bold())
                }
            } else {
                Text("尚未設定防偽密語，這個視窗可能是假的。請執行 pkexec --setup")
                    .font(.callout.bold())
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(phrase == nil ? .red : .green, lineWidth: 2))
    }
}

struct SetupView: View {
    let done: (String?) -> Void
    private final class Field { var text = "" }
    private let field = Field()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("設定防偽密語").font(.title3.bold())
            Text("之後每個 pkexec 視窗都會顯示這句話。沒看到它，就不要輸入密碼。")
                .font(.callout).foregroundStyle(.secondary)
            TextField("例如：藍色鯨魚吃拉麵 🍜", text: Binding(get: { field.text }, set: { field.text = $0 }))
                .onSubmit { save() }
            HStack {
                Spacer()
                Button("取消") { done(nil) }.keyboardShortcut(.cancelAction)
                Button("儲存") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        let phrase = field.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phrase.isEmpty { done(phrase) }
    }
}
