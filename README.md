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
Behind the bar is a **real shell** (a read-eval-print loop): a proper
lexer → parser → AST → evaluator that understands chains (`&&`, `||`), a return
pool (`//`), and variables (`@x`).

The new **[Karet](https://github.com/mkl48/Karet)** — same rigorous backend, a
Cmdr-style surface instead of a windowed terminal. See [DESIGN.md](DESIGN.md).

> **Status: early.** The shell front end is being ported and tested headlessly.
> The lexer is in with specs; the parser, evaluator, registry, completer, and
> the bar UI are next.

## Better than Cmdr

- **Autocomplete** — fuzzy matching and inline ghost-text completion, not a list.
- **Typed args** — inferred from real Luau types, far less boilerplate than Cmdr.
- **Theming** — semantic colorschemes (Tokyonight, Gruvbox, Catppuccin, Nord).
- **Mobile + console** — first-class touch and gamepad entry.
- **A real shell** — chains, a return pool, variables, and proper CS internals.

## Development

```sh
rokit install
lune run tests/run   # headless specs (shell front end)
```

## License

[MIT](LICENSE) — © kr3ative
