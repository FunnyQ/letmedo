# CLAUDE.md

Guidance for Claude Code in this repository.

## What This Is

`letmedo` is a `pkexec` for macOS: an agent asks to run a command as root, a SwiftUI window shows the human what will run and why, and the human approves with Touch ID or a password. It is for Q's own machine only and is never notarized.

- `Sources/LetmedoCore/` holds the pure logic: argument parsing, PATH resolution, argv display, and the sudo steps. Every function here is unit-tested.
- `Sources/letmedo/` holds the windows and the process orchestration. It has no unit tests; verify it end to end with the installed binary.

## Commands

```sh
make test    # swift test with the Testing macro plugin path
make build   # release build
make install # build, then copy to ~/.local/bin/letmedo
```

## Toolchain

This machine has Command Line Tools and no Xcode. That causes two constraints:

- Run tests through `make test`. A bare `swift test` cannot find the `TestingMacros` plugin, because Command Line Tools ship it under `usr/lib/swift/host/plugins/testing/`, outside the default search path.
- Do not use SwiftUI macros such as `@State`. The SDK defines them as macros, and Command Line Tools do not ship the `SwiftUIMacros` plugin. Hold mutable view state in a private reference type and bind to it with `Binding(get:set:)`.

The edit-hook formatter rewrites `\uXXXX` escapes in Swift string literals into the real characters. When a test expects an escaped invisible character, build the backslash with `String(UnicodeScalar(0x5C))` instead of writing it in the literal.

## The sudo flow

`letmedo` runs four sudo steps in this order:

1. `sudo -k` drops any credential left from before.
2. `sudo -v` authenticates through Touch ID. When it fails, `sudo -A -v` authenticates through the password window instead.
3. `sudo -n -- <command>` runs the command, which can never prompt.
4. `sudo -k` drops the credential.

Each step exists because of a measured sudo behaviour on macOS:

- Do not combine `-A` with the Touch ID attempt. When `-A` is set, sudo calls the askpass program and skips `pam_tid`.
- Do not combine `-k` with `-v`. Sudo then authenticates without writing a timestamp, and the `-n` run fails with `a password is required`.
- Without a tty, sudo keys its timestamp by parent process. A second process with a different parent cannot reuse the credential, measured with `sudo -v` in one `sh` and `sudo -n true` in another. That is what keeps an agent's shell out of the window between steps 2 and 4.
- Without a tty, `sudo -k` clears only its own parent's timestamp. Measured with `sudo -v` in one `sh`, `sudo -k` in a second `sh` after the first authenticated, then `sudo -n true` in the first, which still succeeded. That is why one request's steps 1 and 4 cannot break another request's run.

During step 3, `letmedo` ignores SIGHUP, SIGINT, and SIGTERM itself and sends each one to the sudo process. Foundation's `Process` starts sudo in its own process group, so a kill aimed at the agent's process group never reaches sudo. Sudo relays a signal to the command only when the sender is outside sudo's process group, and `letmedo` is outside it.

## The queue

Each `letmedo` writes a ticket named `<nanoseconds>-<pid>` to `~/Library/Caches/letmedo/queue/`. A ticket is waiting while it has no `.done` suffix and its pid is alive. A pass waits while any older ticket is waiting. Only the front pass accepts input. Each waiting pass sits 24pt higher per waiting ticket ahead of it, capped at 3.

After the window closes, `letmedo` renames its ticket to `<name>.done`, so a long command does not hold the queue. The badge shows `n / total`: `n` counts the older tickets plus one, and `total` counts every ticket in the directory, done ones included. When no other ticket is waiting, the batch is over. At start, `letmedo` then deletes every ticket except its own. After the window closes, `letmedo` then deletes every ticket, its own included. Both checks also delete tickets left by killed processes.

## Window rules

- Use a `.nonactivatingPanel`. `NSApp.activate()` is cooperative and is refused when `letmedo` starts from a background shell, which leaves the window without key focus and breaks Escape.
- Set `hidesOnDeactivate` to false, or the pass disappears when another app takes focus.
- Let Tab and Space reach the execute button. Q chose this because Touch ID or the password still gates the run, and `/etc/pam.d/sudo_local` holds only `pam_tid`. Revisit if a rule there ever authenticates without a deliberate act, such as `pam_watchid`.
- Unlock the execute button 0.6s after the pass reaches the front, so a click aimed at another window cannot approve a pass that just appeared.

## Build output

SwiftPM writes products to `.build/out/Products/<Debug|Release>/`, not `.build/debug/`. Use `swift build --show-bin-path` to find the binary.

Touch ID needs `auth sufficient pam_tid.so` in `/etc/pam.d/sudo_local`.

The password window runs as sudo's askpass program. `letmedo` sets `SUDO_ASKPASS` to its own path and `LETMEDO_ASKPASS=1`, and the binary enters askpass mode when it sees that variable.

## Threat model

`letmedo` protects Q from an honest but careless agent. It does not protect against a malicious one, and no feature should claim to.

An anti-phishing phrase stored in the Keychain was built and removed. The agent's terminal holds Screen Recording permission, so a `screencapture` run from the agent's shell captured every window on screen, and any phrase drawn there would be readable. A self-signed binary has no Team ID, so the Keychain bound its ACL to the cdhash and prompted the real binary after every rebuild, the same prompt a fake would raise. A malicious agent can also run `sudo -v` directly and get the same Touch ID prompt with no command attached.

## Security rules

- Show the resolved absolute path of the executable, and pass that same path to sudo, so the displayed command is the one that runs.
- Escape every invisible character in the displayed argv with `$'...'` notation: controls, format characters such as U+202E, separators, private use, and unassigned code points.
- Bind the cancel button to Escape. Never bind the execute button to Return.
- Label the agent's message as a claim. The command line is the source of truth.
- Show "No rule matched" when no rule matches. Never show a command as safe; the rules match strings and an obfuscated script passes them.
- Split only a shell's `-c` script into numbered lines. Escape every other invisible character inside it as its own token.

## Exit codes

| Code | Meaning                                     |
| ---- | ------------------------------------------- |
| 2    | usage error                                 |
| 126  | cancelled, or authentication failed         |
| 127  | command not found                           |
| else | the command's own exit code, or 1 from sudo |
