# pkexec-mac

Let an AI agent ask for root, and let a human decide.

```sh
pkexec -m "Flush the DNS cache so the new hosts entry takes effect" dscacheutil -flushcache
```

The agent runs `pkexec` with a reason. A window shows you the exact command, the agent's reason, which program asked, and the working directory. You approve with Touch ID, or with your password when Touch ID is unavailable. The command's output and exit code go back to the agent. The agent never sees your password and never keeps root afterwards.

## Requirements

- macOS 15 or later
- Swift 6 (Command Line Tools are enough)
- Touch ID for sudo, enabled in `/etc/pam.d/sudo_local`:

  ```sh
  sudo sh -c 'sed "s/^#auth/auth/" /etc/pam.d/sudo_local.template > /etc/pam.d/sudo_local'
  ```

- A code-signing identity named `pkexec-local` in the login keychain. A self-signed certificate with the code signing extended key usage works.

## Build

```sh
make test
make build    # writes and signs .build/release/pkexec
```

## Set up the anti-phishing phrase

```sh
.build/release/pkexec --setup
```

Pick a phrase only you know. Every `pkexec` window shows it in a green box. If a window asks for your password and does not show your phrase, it is fake. Do not type your password into it.

The phrase lives in your login keychain, and only the signed `pkexec` binary can read it without a prompt. If a Keychain prompt asks to let another program read `cc.funnyq.pkexec`, deny it.

## Usage

```sh
pkexec [-m message] <command> [args...]
```

- `-m message` is the agent's reason. The window labels it as a claim.
- `<command>` is resolved through `PATH` to an absolute path, and the window shows that path.

## How it works

1. `pkexec` resolves the command and shows the confirm window.
2. On approval, it asks sudo to authenticate with Touch ID.
3. If Touch ID fails, it shows its own password window and passes your password to sudo as its askpass helper.
4. It runs the command through `sudo -n`, then drops the sudo credential at once.

## Security notes

- The displayed argv escapes invisible characters, so a right-to-left override or an ANSI escape cannot hide part of the command.
- The execute button does not respond to Return, so a burst of requests cannot be approved by a held key.
- The sudo credential is keyed to the `pkexec` process, so another process cannot reuse it while the command runs.
- A fake window can copy the design, but it cannot read your phrase. Check the phrase every time.
