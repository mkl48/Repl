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
> networking, and the Fusion bar/UI are being built up the pipeline.

Built on **[Switch](https://github.com/mkl48/Switch)** (input) and
**[Substance](https://github.com/mkl48/Substance)** (networking), with a
**[Fusion](https://elttob.uk/Fusion/)** UI. Docs by **[Docket](https://github.com/mkl48/Docket)**.

## Structure

A game-framework layout. `_`-prefixed folders are internal; everything a game
author writes lives under `_Commands/`.

```
Repl                       -- the umbrella ModuleScript (returns the API)
  _Classes/                -- OOP pieces you .new()
    Command · Argument · Context · Type · Session
  _Main/                   -- the entry points
    Server                 -- Registry + Dispatcher, hooks, authority, authoritative run
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

## Quick start

**Server** — register commands/types and wire up authority:

```lua
local Repl = require(game.ReplicatedStorage.Repl)

Repl:Start({
    Commands = { game.ServerStorage.Commands },   -- folders auto-loaded
    Types    = { game.ServerStorage.Types },
})

Repl.Authority:DefineRole("Admin", { "players.*", "server.announce" })
Repl.Authority:SetResolver(function(player)
    return player.UserId == OWNER_ID and "Owner" or "Player"
end)
```

**Client** — the bar:

```lua
local Repl = require(game.ReplicatedStorage.Repl)

Repl:Start({ Activation = { Enum.KeyCode.Semicolon }, Theme = "tokyonight" })
Repl:Show() / :Hide() / :Toggle()
Repl:Execute("kill /Player && announce done")   -- run a line programmatically
```

## Commands

A command is a ModuleScript under `_Commands/_Shared` (or `_Client` / `_Server`).
Arguments are declared with a terse **string DSL** — `name: TypeExpr [= default]`
— and arrive already typed and validated in the handler.

```lua
return {
    Name = "kill",
    Aliases = { "slay" },
    Description = "Kill a player.",
    Capabilities = { "players.kill" },       -- capability-based auth
    Confirm = "Kill everyone matched?",      -- optional y/n before Run
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

### Types that autocomplete themselves

The text after the colon is a real **type expression**, compiled by `_Main/Types`
— not a lookup. Unions, intersections, and **ranges that enumerate their valid
values**:

```lua
Args = {
    "target: Player | Character",     -- union: either
    "id: Number & Int32",             -- intersection: both
    "count: 2 < Number < 30",         -- range: autocompletes 3…29
}
```

Custom types live in `_Commands/_Types`, with optional **expansions** (sigil
shortcuts like `*` = everyone, `%Raiders` = a team):

```lua
return {
    Name = "Players",
    Transform = function(raw) return ... end,
    Validate  = function(value) return ok, why end,
    Autocomplete = function(value) return { ... } end,
    Expansions = { ["*"] = allPlayers, ["%"] = teamOf },
}
```

## The Context — terminal semantics

Passed to every handler. Structured output, exit codes, confirm prompts, and
running other commands:

```lua
ctx:reply(t) · :success(t) · :error(t) · :warn(t) · :info(t) · :custom(color, t)
ctx:ascii(art) · :table(rows) · :status(kind, t) · :icon(id, t)    -- rich output
ctx:confirm(q):await() · :prompt(q) · :choose(q, opts)             -- ask the executor
ctx:exec(name, ...)                                                -- run another command
ctx:ok(...) · :err(code, msg) · :abort(msg) · :return(...)         -- Result + return pool
ctx.executor · ctx.rawText · ctx.args · ctx.realm · ctx:store(name)
```

Output is **structured, not strings** — a command builds an Output tree
(`Segment` / `Line` / `Block`) and one Fusion renderer draws it: replies, ascii,
tables, icons, status spinners, all live-themed.

## Authority — capability-based

Not role tiers. Commands declare capabilities; roles are capability bundles with
wildcards; a resolver maps players → roles (async — group rank / gamepass /
DataStore); policies can inspect the *args* for fine-grained rules.

```lua
Repl.Authority:DefineRole("Mod",   { "players.kick", "chat.mute" })
Repl.Authority:DefineRole("Admin", { extends = "Mod", grants = { "players.*" } })
Repl.Authority:DefineRole("Owner", { "*" })
Repl.Authority:Grant(player, "players.teleport")   -- one-off · :Revoke · :Has
```

All checks run server-side before the handler; the client never decides.

## The UI toolkit — `Repl.UI`

A widget toolkit in the same skin, so you build menus and dashboards that match
the bar. **Immediate-mode** (ImGui / Iris style — call widgets in a loop) driven
by Fusion underneath, so it's live-themed and animated:

```lua
local UI = Repl.UI
UI:Window("Server Stats", function()
    UI:Text(`uptime: {up}`)
    UI:Graph(fpsHistory, { kind = "line" })
    UI:Table(players, { "Name", "KDR", "Ping" })
    if UI:Button("restart") then restartServer() end
end)
```

Windows · Menus · Tabs · Tree · Graph · Chart · Table · Sparkline · Progress ·
Log · Chat — all themed, all animated.

## Theming

Semantic colorschemes piped through the whole bar, terminal, and toolkit — swap
one and everything recolors live:

```lua
Repl.Theme:Set("tokyonight")   -- gruvbox · catppuccin · nord, or Define your own
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

The full design lives in **[DESIGN.md](DESIGN.md)**.

## License

[MIT](LICENSE) — © kr3ative
