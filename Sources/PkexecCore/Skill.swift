public let skill = #"""
---
name: pkexec
description: Run a command as root on the user's Mac by asking the user through the pkexec approval window. Use whenever a task needs root or sudo — editing /etc, writing under /Library or /usr, launchctl for system daemons, flushing system caches, installing system files. Do NOT run sudo directly and do NOT ask the user for a password.
---

# pkexec

`pkexec` shows the user a card with the exact command, your reason, your shell, your working directory, and the time. The user approves with Touch ID or a password. The command then runs as root, and its output and exit code come back to you.

```sh
pkexec -m "<why, in one sentence>" <command> [args...]
```

The binary lives at `~/.local/bin/pkexec`. When `command -v pkexec` finds nothing, tell the user, who installs it with `make install` in the pkexec-mac repo. `pkexec --skill` prints this skill.

## Rules

1. Use `pkexec` for every root command. Never run `sudo` yourself, and never ask the user for a password.
2. Write `-m` as a claim the user can check against the command: what it does and why the task needs it. "Add the dev hostname to /etc/hosts so the local server resolves" — not "fix it".
3. Pass the command as plain arguments. The user reads each argument on its own numbered line, so `pkexec -m "…" launchctl bootout system/com.example.helper` is easier to judge than a shell string.
4. Use `sh -c '…'` only when the work needs a pipe, a redirect, or several steps. The user sees the script split into numbered lines, and the card flags it as a shell string.
5. Write to a root-owned file with `tee` on stdin instead of a redirect inside `sh -c`. Stdin passes through to the command:

   ```sh
   printf '127.0.0.1 dev.local\n' | pkexec -m "Map dev.local to localhost for the local server" tee -a /etc/hosts
   ```

6. Run only non-interactive commands. There is no tty, so a command that prompts will read your stdin or hang.
7. Request one action per call. Several calls at once are fine: they queue as a stack, numbered `1 / n`, and the user answers them in order.
8. `cd` to the relevant directory first. The card shows your working directory as context.

## Waiting for the user

The window has no timeout. The user may be away, so run `pkexec` with a long tool timeout or in the background. When your tool kills the call, `pkexec` receives SIGTERM. Before approval, `pkexec` treats it as a cancel and exits 126. After approval, `pkexec` passes SIGINT and SIGTERM on to the running command.

## Exit codes

| Code | Meaning                                      | What to do                                              |
| ---- | -------------------------------------------- | ------------------------------------------------------- |
| 0    | the command succeeded                        | continue                                                |
| 2    | usage error                                  | fix the call: `-m` needs a value, a command must follow |
| 126  | the user cancelled, or authentication failed | stop; ask the user before you retry or try another way  |
| 127  | command not found on `PATH`                  | pass an absolute path or fix the name                   |
| else | the command's own exit code, or 1 from sudo  | read stderr as you would for any command                |

A 126 is the user's answer. Do not retry the same request in a loop, and do not look for another route to root.

## What the card flags

The card marks recursive deletes in red, and shell strings and system paths in amber. These are string matches. "No rule matched" does not mean the command is safe, so your `-m` still has to explain the risk.

"""#
