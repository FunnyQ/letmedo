# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS SwiftUI app built with Command Line Tools only. The schema's values (`web`, `ios`, `android`, `adaptive`) do not cover macOS; follow AppKit and macOS Human Interface conventions.

## Users

Q, on Q's own Mac. Q usually watches an agent work in a terminal and expects a root request. When several agents run at once, the request interrupts other work and must take attention without inviting a reflex approval.

## Product Purpose

`pkexec` lets an AI agent ask to run one command as root and lets Q decide. Success: Q reads exactly what will run, judges it in seconds, and approves with Touch ID or a password, or cancels with Escape.

## Positioning

The resolved command line is the source of truth. The agent's message is a claim. The window exists to make that difference readable.

## Operating Context

- The agent runs `pkexec -m "why" <cmd> [args...]` from its shell.
- The confirm window shows the resolved command, the agent's claim, the requester process path, the cwd, and the request time.
- The password window runs as sudo's askpass program when Touch ID fails.
- Commands range from short (`dscacheutil -flushcache`) to long argv lists and `sh -c` with a multi-line script.

## Capabilities and Constraints

- Show the resolved absolute executable path; the displayed command is the command that runs.
- Escape invisible characters in the argv with `$'...'` notation.
- Bind cancel to Escape. Never bind execute to Return.
- Do not use SwiftUI macros such as `@State`; Command Line Tools lack the macro plugin.
- Show no anti-phishing phrase; see the threat model in CLAUDE.md.
- Planned: format and colour the command for reading, and flag risky commands with simple rules in `PkexecCore`.

## Product Principles

1. The command is the loudest thing on screen.
2. The agent's words never look like the system's words.
3. Approval takes a deliberate mouse action; cancel is one key.
4. Protect against a careless agent; never claim protection against a malicious one.
