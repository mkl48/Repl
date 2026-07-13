# Repl icons

White [Lucide](https://lucide.dev) glyphs (MIT), 256×256 PNGs on transparent
backgrounds so Roblox can tint them to the theme via `ImageColor3`.

- `png/` — upload these to Roblox (Decals).
- `svg/` — the sources, if you want to re-export at another size.

## Wiring them up

After uploading, hand the asset ids to the icon map — either in
`src/_Utility/Render/Icons.luau` directly, or at runtime:

```lua
local Repl = require(game.ReplicatedStorage.Repl)

Repl.Icons.setMany({
    ["check"] = 1234567890,          -- a number or a full "rbxassetid://…"
    ["x"] = 1234567891,
    ["warn"] = 1234567892,
    ["info"] = 1234567893,
    -- …
})
```

Semantic aliases (`success`→`check`, `error`→`x`, `warn`, `prompt`→`chevron-right`,
…) resolve automatically, so `ctx:icon("success", "saved")` and status line kinds
Just Work once the base glyphs have ids.

Until an id is set, the terminal renders `[name]` as text — nothing breaks.
