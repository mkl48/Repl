--- The **icon map**: icon name → Roblox asset id. The PNGs live in
--- `assets/icons/png` (white, so they tint to the theme via `ImageColor3`) — upload
--- them and fill in the ids below, or set them at runtime with `Icons.set` /
--- `Repl.Icons.set(name, "rbxassetid://…")`. Until an id is set, the [[Terminal]]
--- falls back to rendering `[name]` as text, so nothing breaks.
---
--- Semantic aliases (`success`, `error`, `warn`, `prompt`, …) map onto the base
--- glyphs so `ctx:icon("success", …)` and Output line kinds resolve without
--- knowing the underlying icon.
--- @section Render
--- @client

local Icons = {}

--- name → `rbxassetid://…`. Fill these after uploading `assets/icons/png/*`.
Icons.assets = {
	["check"] = nil :: string?,
	["x"] = nil :: string?,
	["info"] = nil :: string?,
	["warn"] = nil :: string?,
	["chevron-right"] = nil :: string?,
	["chevron-down"] = nil :: string?,
	["terminal"] = nil :: string?,
	["circle-check"] = nil :: string?,
	["circle-x"] = nil :: string?,
	["circle-alert"] = nil :: string?,
	["arrow-right"] = nil :: string?,
	["search"] = nil :: string?,
	["folder"] = nil :: string?,
	["zap"] = nil :: string?,
	["clock"] = nil :: string?,
	["user"] = nil :: string?,
	["hash"] = nil :: string?,
	["play"] = nil :: string?,
	["settings"] = nil :: string?,
	["list"] = nil :: string?,
} :: { [string]: string? }

--- semantic name → base glyph
Icons.aliases = {
	success = "check",
	error = "x",
	err = "x",
	warn = "warn",
	warning = "warn",
	info = "info",
	prompt = "chevron-right",
	ok = "circle-check",
	fail = "circle-x",
	alert = "circle-alert",
	help = "info",
	commands = "list",
	time = "clock",
}

--- Resolves an icon name (or alias) to its asset id, or nil if unset.
function Icons.resolve(name: string): string?
	local base = Icons.aliases[name] or name
	return Icons.assets[base]
end

--- Sets an asset id for a base icon name (accepts a number or a full string).
function Icons.set(name: string, assetId: string | number)
	if type(assetId) == "number" then
		assetId = `rbxassetid://{assetId}`
	end
	Icons.assets[name] = assetId
end

--- Bulk-set from a `{ [name] = id }` table.
function Icons.setMany(map: { [string]: string | number })
	for name, assetId in map do
		Icons.set(name, assetId)
	end
end

return Icons
