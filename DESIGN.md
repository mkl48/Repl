# Repl — design

**Repl** is an in-game command bar for Roblox: press the activation key, a single
bar slides in, you type a command, and it runs — server-authoritative, typed,
themed. It looks like [Cmdr](https://eryn.io/Cmdr/) on the surface, but behind
the bar is a **real shell** (a read-eval-print loop, hence the name): a proper
lexer → parser → AST → evaluator that understands chains, pipes, a return pool,
and variables.

The name is literal: a **REPL**. Read a line, evaluate it through the shell,
print the result, loop.

## What it is (decided)

- **Surface: a command bar only.** No windowed terminal. The bar slides in on an
  activation key, autocomplete hangs above it, output prints inline. (Karet v1's
  windowed Terminal is retired.)
- **Grammar: the full shell.** One-command-with-typed-args is the common case,
  but the whole grammar works in the bar — chains (`&&`, `||`, `&`), the return
  pool (`//`, `/Player`, `/target#2`), variables (`@x`), expressions, guards.
  Ported and evolved from Karet v1's `Shell`.
- **Identity: fresh.** New name, new repo (`mkl48/Repl`). Karet v1 stays as-is;
  Repl carries over v1's proven backend but is its own project.

## Better than Cmdr (the priorities)

1. **Autocomplete UX** — fuzzy matching, inline **ghost-text** completion (the
   grey suggestion you accept with Tab/→), argument previews, not just a list.
2. **Typed-arg ergonomics** — argument types inferred from real **Luau type
   annotations** on the handler where possible, plus a terse arg syntax; far less
   boilerplate than Cmdr's verbose type definitions.
3. **Theming** — semantic themes (Tokyonight / Gruvbox / Catppuccin / Nord) with
   live recolor, carried from Karet. Cmdr's UI is rigid; Repl's is a colorscheme.
4. **Mobile + console** — first-class touch and gamepad entry (via Switch), which
   Cmdr handles poorly.
5. **Proper CS architecture & terms** — the pipeline is named for what it is:
   `Lexer` (tokens), `Parser` (AST), `Evaluator`, `ReturnPool`, `Registry`,
   `Completer`. No dumbed-down names.
6. **Terminal behaviours** — even as a bar: command **history** (up/down), tab
   completion, full cursor editing, a REPL prompt, structured output.

## Architecture (pipeline)

```
keypress ─▶ Bar (input, cursor, history) ─▶ Lexer ─▶ Parser ─▶ AST
                    │                                              │
              Completer ◀── Registry (typed commands) ────────────┤
                    │                                              ▼
              ghost text / hints                              Evaluator
                                                                   │
                                            Context + Networking (Substance, authoritative)
                                                                   ▼
                                                           Output (printed inline)
```

- **Bar** — the on-screen surface: one input line, cursor, history, ghost text,
  the autocomplete popover, inline output. Themed.
- **Lexer / Parser / AST** — the shell front end (ported from Karet v1's `Shell`).
- **Registry** — typed command definitions; arg types inferred from Luau where
  possible.
- **Completer** — fuzzy + ghost-text suggestions from the registry and the
  current AST/cursor position.
- **Evaluator** — walks the AST, resolves args, runs handlers, manages the
  return pool and variables.
- **Context / Networking** — server-authoritative execution over Substance
  (Karet v1's model); the client never runs privileged commands.
- **Theme** — semantic colorscheme piped through the whole bar.

## Carried over from Karet v1

Port and evolve (don't rewrite): `Shell` (Lexer/Parser/Evaluator/Ast/ReturnPool),
`Registry`/`Commands`, `Types`, `Context` + `Networking`, `Theme`, and the
headless test approach (v1 had 90 specs). Retire: the windowed `Terminal`, Iris,
Kaveat (the Luau editor), the WindowManager.

Dependencies: **Switch** (input), **Substance** (networking). Docs: **Docket**
from day one.

## Build order (proposed)

1. Scaffold: repo, rokit/wally, project json, deps, Docket config.
2. Shell core: port Lexer → Parser → AST → Evaluator + ReturnPool, with headless
   specs. (Pure Luau, testable without Roblox.)
3. Registry + typed args (Luau-inferred), with specs.
4. Completer (fuzzy + ghost text), with specs.
5. The Bar UI (Switch input, cursor/history/output, theme) — Studio-verified.
6. Context + Networking (Substance, authoritative).
7. Docs (Docket), installer, release.
