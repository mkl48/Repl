<div align="center">

# Repl

**An in-game command bar for Roblox, backed by a real shell.**

<img src="https://img.shields.io/badge/Repl-v0.1.0-7aa2f7?style=for-the-badge" alt="version" />
<img src="https://img.shields.io/badge/Luau-Roblox-00A2FF?style=for-the-badge" alt="luau" />
<img src="https://img.shields.io/badge/License-MIT-9ece6a?style=for-the-badge" alt="license" />
<img src="https://img.shields.io/badge/Status-Early-e0af68?style=for-the-badge" alt="status" />

**[Read the docs](https://mkl48.github.io/Repl/)** · Looks like Cmdr, thinks like a shell

</div>

---

Repl is a command bar you drop into a Roblox game: press the activation key, type
a command, and it runs — server-authoritative, typed, themed. On the surface it's
[Cmdr](https://eryn.io/Cmdr/); behind the bar is a real shell (a read-eval-print
loop) with chains, a return pool, and variables. It's the new
[Karet](https://github.com/mkl48/Karet), and a standalone module — one
`require(ReplicatedStorage.Repl)` returns the whole API.

> **Status: early.** The shell front end (lexer → parser → AST) is in and tested.
> The type engine, registry, authority, context, networking, and the Fusion
> bar/UI are being built. Everything is on the **[docs site](https://mkl48.github.io/Repl/)**.

## Installation

Paste this into the Studio command bar (enable *Game Settings → Security → Allow
HTTP Requests*); it recreates the tree under `ReplicatedStorage.Repl`:

```lua
local h = game:GetService("HttpService")
loadstring(h:GetAsync("https://raw.githubusercontent.com/mkl48/Repl/master/dist/install.luau"))()
```

## Development

```sh
rokit install
lune run tests/run   # headless specs (shell front end)
```

## License

[MIT](LICENSE) — © kr3ative
