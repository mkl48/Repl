<div align="center">

# Repl

**An in-game command bar for Roblox, backed by a real shell.**

<img src="https://img.shields.io/badge/Repl-v0.1.0-7aa2f7?style=for-the-badge" alt="version" />
<img src="https://img.shields.io/badge/Luau-Roblox-00A2FF?style=for-the-badge" alt="luau" />
<img src="https://img.shields.io/badge/License-MIT-9ece6a?style=for-the-badge" alt="license" />
<img src="https://img.shields.io/badge/Status-Early-e0af68?style=for-the-badge" alt="status" />

Looks like Cmdr. Thinks like a shell.

</div>

---

Repl is a command bar you drop into a Roblox game: press the activation key, a
single bar slides in, and you type a command. On the surface it's
[Cmdr](https://eryn.io/Cmdr/) — one line, typed arguments, inline autocomplete.
Behind the bar is a **real shell** (a read-eval-print loop, hence the name): a
proper lexer → parser → AST → evaluator that understands chains (`&&`, `||`), a
return pool (`//`), and variables (`@x`).

The new **[Karet](https://github.com/mkl48/Karet)** — same rigorous backend, a
Cmdr-style surface instead of a windowed terminal. It's a **standalone module**:
one `require(ReplicatedStorage.Repl)` returns the whole API.

> **Status: early.** The shell front end (lexer → parser → AST) is in and tested
> (`lune run tests/run`). The type engine, registry, authority, context,
> networking, and the Fusion bar/UI are being built up the pipeline. The full
> design is in **[DESIGN.md](DESIGN.md)**.

## What makes it better than Cmdr

- **Autocomplete** — fuzzy matching and inline ghost-text completion, not a list.
- **Typed args** — a terse `Args` string DSL, with a real type-expression compiler:
  unions `Player | Character`, intersections `Number & Int32`, and ranges
  `2 < Number < 30` that **autocomplete the valid values**.
- **A capability-based auth system** — roles are capability bundles with wildcards,
  an async resolver, and per-argument policies. Server-authoritative.
- **Structured terminal output** — replies, status, tables, ascii, icons, confirm
  prompts — all one themed renderer.
- **A UI toolkit** — `Repl.UI`, an immediate-mode (ImGui/Iris-style) widget system
  in the same skin: windows, graphs, charts, tables.
- **Semantic theming** — Tokyonight / Gruvbox / Catppuccin / Nord, live recolor.
- **Mobile + console** — first-class touch and gamepad entry.

## A command

```lua
-- _Commands/_Shared/kill.luau
return {
    Name = "kill",
    Aliases = { "slay" },
    Description = "Kill a player.",
    Capabilities = { "players.kill" },
    Args = {
        "victim: Players",
        "amount: Integer? = 1",
    },
    Run = function(ctx, victim, amount)
        for _, p in victim do p.Character:BreakJoints() end
        return ctx:ok(`killed {#victim}`)
    end,
}
```

## Installation

### Command bar (no toolchain)

Paste this one snippet into the Studio command bar; it fetches and runs the full
installer over HTTP (enable *Game Settings → Security → Allow HTTP Requests*),
recreating the whole tree under `ReplicatedStorage.Repl`:

```lua
local h = game:GetService("HttpService")
loadstring(h:GetAsync("https://raw.githubusercontent.com/mkl48/Repl/master/dist/install.luau"))()
```

([`dist/bootstrap.luau`](dist/bootstrap.luau) is the same with error handling.)
Or, offline, paste the whole [`dist/install.luau`](dist/install.luau) directly.
Regenerate it from source any time with `lune run scripts/build-installer`.

## Development

```sh
rokit install
lune run tests/run   # headless specs (shell front end)
```

## License

[MIT](LICENSE) — © kr3ative
