# Repl — design

**Repl** is an in-game command bar for Roblox: press the activation key, a single
bar slides in, you type a command, and it runs — server-authoritative, typed,
themed. On the surface it's [Cmdr](https://eryn.io/Cmdr/). Behind the bar is a
**real shell** — a read-eval-print loop (hence the name): lexer → parser → AST →
evaluator, with chains, a return pool, and variables.

It is a **standalone module**, like Karet: one `require(ReplicatedStorage.Repl)`
returns the whole API; there's nothing to wire together.

## Structure

A game-framework layout. `_`-prefixed folders are internal; user content lives
under `_Commands/`.

```
Repl                       -- the umbrella ModuleScript (returns the API)
  _Classes/                -- OOP pieces you .new()
    Command · Argument · Context · Type · Session
  _Main/                   -- the entry points
    Server                 -- Registry + Dispatcher, hooks, auth, authoritative run
    Client                 -- the bar UI (Fusion), activation, history, rendering
    Types                  -- the type engine: built-ins + the type-expression compiler
    Network                -- Substance transport (server-authoritative)
  _Patterns/               -- domain-agnostic CS primitives
    Result · Option · Stream
  _Utility/                -- helpers
    Shell/ (Lexer, Token, Parser, Ast, Evaluator, ReturnPool) · Fuzzy · Render
  _Commands/               -- everything a game author writes
    _Client/ · _Server/ · _Shared/   -- command defs, by realm
    _Types/                          -- custom argument types, by name
  _Packages/               -- vendored deps
    Promise · GoodSignal · Janitor · Substance · Switch · Fusion · t
```

## The command bar (client) API

```lua
local Repl = require(game.ReplicatedStorage.Repl)

Repl:SetActivationKeys({ Enum.KeyCode.Semicolon })   -- Switch-backed, cross-platform
Repl:Show() / :Hide() / :Toggle()
Repl:Execute("kill /Player && announce done")        -- run a line programmatically
Repl.Theme:Set("tokyonight")                         -- semantic colorscheme, live recolor
```

## The registry (server) API

```lua
Repl.Registry:RegisterCommandsIn(ServerStorage.Commands)   -- folders of defs
Repl.Registry:RegisterTypesIn(ServerStorage.Types)
Repl.Registry:RegisterCommand(def)                          -- one at a time
Repl.Registry:RegisterType(name, typeDef)
Repl.Registry:RegisterHook("BeforeRun" | "AfterRun", fn)
Repl.Registry:GetStore(name)                                -- shared cross-command state
```

## Commands — the schema

A command is a ModuleScript under `_Commands/_Shared` (or `_Client`/`_Server`).
Its arguments are declared with a terse **string DSL** — `name: TypeExpr [= default]`
— far less boilerplate than Cmdr's arg tables. Args arrive already typed and
validated in the handler.

```lua
return {
    Name = "kill",
    Aliases = { "slay" },
    Description = "Kill a player.",
    Capabilities = { "players.kill" },    -- auth (see below)
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

### The type-expression language (the "better than Cmdr")

The text after the colon is a real **type expression**, compiled by `_Main/Types`
into a resolved [[Type]] with merged validation + autocomplete. It is a *compiler*,
not a lookup:

| Form | Meaning | Autocomplete |
| --- | --- | --- |
| `Player` | a single type | that type's suggestions |
| `Player \| Character` | **union** (either) | both sets merged |
| `Number & Int32` | **intersection** (both) | A's suggestions filtered by B |
| `2 < Number < 30` | **range / conditional** | **enumerates the valid values** (3…29) |
| `Number >= 0` | open-ended bound | — |
| `(A \| B) & C` | grouping | composed |

Grammar (low→high precedence): `Union(|) → Intersection(&) → Range(bounded atom) → Atom(TypeName | "(" expr ")")`.

## Argument types — the schema

Under `_Commands/_Types`. A type transforms raw text → an intermediate, validates
it, and offers autocomplete + optional **expansions** (sigil shortcuts):

```lua
return {
    Name = "Players",
    Transform = function(raw) return ... end,      -- text -> intermediate
    Validate  = function(value) return ok, why end,
    Autocomplete = function(value) return { ... } end,
    Parse = function(value) return value end,        -- intermediate -> final
    Expansions = {                                   -- typed shortcuts
        ["*"] = function() return Players:GetPlayers() end,   -- everyone
        ["%"] = function(team) return teamOf(team) end,       -- %Raiders
    },
}
```

## The Context — terminal semantics

Passed to every handler (`_Classes/Context`). This is where the terminal lives:
structured output, exit codes, streams, and running other commands.

```lua
-- output (all build the structured Output tree, drawn by the renderer)
ctx:reply(t) · :success(t) · :error(t) · :warn(t) · :info(t) · :message(t)
ctx:custom(color, t) · :ascii(art) · :table(rows) · :status(kind, t) · :icon(id, t)
-- interaction
ctx:suggest(list)                 -- push autocomplete suggestions
ctx:exec(name, ...)               -- run another command, returns its Result
ctx:prompt(q) / :confirm(q)       -- ask the executor (async -> Reaction)
-- flow / result
ctx:ok(...) · :err(code, msg) · :abort(msg)   -- exit with a Result
ctx:return(...)                   -- push to the shell return pool (//)
-- identity / state
ctx.executor · ctx.rawText · ctx.args · ctx.realm · ctx:store(name)
```

## Terminal rendering

**Output is structured, not strings.** A command builds an Output tree; a reusable
renderer draws it. That is what makes ascii/icons/status/multiline all one system.

- **`Segment`** = `{ text, color, bold?, italic?, icon?, link? }` (the atom).
- **`Line`** = list of segments. **`Block`** = list of lines (multiline, ascii, tables, panels).
- A builder/markup API composes them (`ctx:reply()` returns a builder).
- The **renderer** (`_Utility/Render`, in **Fusion**) maps the Output tree to
  instances: RichText labels, inline icons (Lucide), status spinners/glyphs. Colors
  are `Computed` off the theme `Value`, so recolor is live; `Spring` drives the
  slide-in, ghost-text fade, and status animation.

## Authentication — capability-based

Not role tiers (User < Admin < Owner). **Capabilities**, composed:

- Commands declare **`Capabilities`** (e.g. `{ "players.kill" }`), not a level.
- **Roles are bundles of capabilities**, with wildcards:
  `Admin = { "players.*", "server.announce" }`, `Owner = { "*" }`.
- A **resolver hook** maps player → roles (group rank, gamepass, attribute, DataStore);
  it may be **async** (returns a Reaction/Promise).
- **Policies** are predicates that inspect the *args*, not just the command — e.g.
  "targeting others needs `players.kill.others`; targeting self needs only
  `players.kill`". Context-aware, per-argument.
- All checks run **server-side** in `_Main/Server` before the handler; the client
  never decides.

## Classes & Patterns

- **Classes** (`.new()`): `Command`, `Argument`, `Context`, `Type`, `Session`.
- **Patterns** (CS primitives the packages don't give us): `Result` (Ok/Err — the
  terminal-correct return), `Option` (Some/None), `Stream` (structured output sink).
- Everything else comes from **Packages**: GoodSignal (events), Janitor (cleanup),
  Promise + Substance Reaction (async), Substance (networking), Switch (input),
  Fusion (UI), t (runtime type checks). Fuzzy matching is `_Utility/Fuzzy`.

## Build order

Front-to-back, each headless-testable until the UI:

1. **Shell** — Lexer (done) → Parser → AST → Evaluator + ReturnPool. Specs.
2. **Type engine** — the type-expression compiler (union/intersection/range),
   built-in types, autocomplete composition. Specs.
3. **Registry** — command + type registration, the `Args` string-DSL parser,
   hooks. Specs.
4. **Auth** — capabilities, roles, policies, resolver. Specs.
5. **Context + Result/Option/Stream + Output model.** Specs.
6. **Network** — Substance transport, server-authoritative dispatch.
7. **Client / Bar** — Fusion UI, Switch input, the renderer, history, ghost text.
8. Docs (Docket), installer, release.
