# easy-dotnet.nvim — Copilot Instructions

## What This Repo Is

This is the **Lua Neovim client** for the easy-dotnet plugin. It is intentionally dumb. Its only responsibilities are:

- Spawning and managing the server process lifecycle
- Dispatching outgoing JSON-RPC calls via `./lua/easy-dotnet/rpc/`
- Handling reverse requests from the server (show a picker, prompt for input, display a float)
- Rendering data the server returns into Neovim buffers and windows

All intelligence, state, and business logic lives in the server (`easy-dotnet-server`). If you find yourself writing conditional logic about .NET concepts, project state, or build output in Lua — stop and move it to the server instead.

> **If you are about to make changes that affect the JSON-RPC wire contract** (adding, removing, or changing any method name, parameter shape, or return type), you must read the server repo's instructions first:
> `$HOME/repo/easy-dotnet-server/.github/copilot-instructions.md`
> Both sides must be updated atomically. The protocol is the contract.

---

## Architecture Principles

### The Client Is Dumb by Design

> **Lua is hard to maintain. C# is not.** Resist the urge to add logic here. The server decides what to show and when; the client just shows it.

- No knowledge of MSBuild, NuGet, Roslyn, solution structure, or .NET tooling belongs in this repo.
- The server drives complex workflows via **reverse requests** — it sends requests to the client mid-operation to collect input or display progress. The client fulfills them and replies.

### Reverse Requests

The server initiates requests to the client during long-running operations. Study the existing handlers in `./lua/easy-dotnet/rpc/` before adding new ones — all reverse request handlers live there.

The flow:

```
Client calls server  →  server does async work
  →  server sends reverse request ("pick a project")
  →  client shows picker, replies with selection
  →  server continues, sends progress notifications
  →  server sends final result
```

### JSON-RPC Contract

- **JSON-RPC 2.0** over stdin/stdout.
- Method names use **dot notation** by domain: `testRunner.run`, `project.restore`, `editor.navigate`.
- `rpcDoc.md` (in the server repo) is the hand-maintained wire contract. Read it before implementing any new RPC call.

---

## Code Guidelines

- **No business logic.** Rendering, picking, and prompting only.
- Follow the dispatcher pattern in `./lua/easy-dotnet/rpc/`. New reverse request handlers belong there.
- Use `vim.schedule()` to re-enter the Neovim event loop from async/RPC callbacks.
- Prefer Neovim built-in APIs (`vim.ui.select`, `vim.ui.input`) for simple interactions — keeps the client thin and theme-compatible.
- All `require()` calls use the `easy-dotnet` namespace prefix.
- When working with Neovim-specific APIs (extmarks, `vim.ui`, floating windows, treesitter, etc.), **searching the internet is encouraged**. The Neovim docs and source are dense — community examples and GitHub issues often clarify real behavior faster than the reference docs.

---

## Key Files

| File | What it teaches |
|---|---|
| `lua/easy-dotnet/rpc/` | RPC dispatcher and all reverse request handlers |

When adding a new user-facing feature, the workflow is: define the RPC contract → implement it in the server → add only the render/input handler here.
