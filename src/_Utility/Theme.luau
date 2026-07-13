--- The **Theme**. Every color in Repl — terminal output, the bar chrome, every
--- [[Output]] Segment, every Repl.UI widget — is named by a *semantic token*
--- (`accent`, `success`, `error`, `bg`, `prompt`…), never a literal color. A
--- theme maps those tokens to a palette; `Set` swaps the palette and notifies
--- listeners, which is what makes the whole surface recolor live. Ships
--- tokyonight, gruvbox, catppuccin, and nord.
---
--- The palette values are hex strings so the engine stays headless; `Color3`
--- resolves them at the Roblox boundary (`Theme:Color3(token)`).
--- @section Theme
--- @client

local Theme = {}

--- The full token set every palette must define.
export type Token =
	"bg" | "bgAlt" | "text" | "muted" | "accent" | "success" | "error" | "warn" | "info" | "border" | "selection" | "cursor" | "prompt"

export type Palette = { [string]: string }

local TOKENS: { string } = {
	"bg", "bgAlt", "text", "muted", "accent",
	"success", "error", "warn", "info",
	"border", "selection", "cursor", "prompt",
}

local PALETTES: { [string]: Palette } = {
	tokyonight = {
		bg = "#24283b", bgAlt = "#1f2335", text = "#c0caf5", muted = "#565f89", accent = "#7aa2f7",
		success = "#9ece6a", error = "#f7768e", warn = "#e0af68", info = "#7dcfff",
		border = "#414868", selection = "#364a82", cursor = "#c0caf5", prompt = "#bb9af7",
	},
	gruvbox = {
		bg = "#282828", bgAlt = "#1d2021", text = "#ebdbb2", muted = "#928374", accent = "#83a598",
		success = "#b8bb26", error = "#fb4934", warn = "#fabd2f", info = "#8ec07c",
		border = "#3c3836", selection = "#504945", cursor = "#ebdbb2", prompt = "#d3869b",
	},
	catppuccin = {
		bg = "#1e1e2e", bgAlt = "#181825", text = "#cdd6f4", muted = "#6c7086", accent = "#89b4fa",
		success = "#a6e3a1", error = "#f38ba8", warn = "#f9e2af", info = "#94e2d5",
		border = "#313244", selection = "#45475a", cursor = "#f5e0dc", prompt = "#cba6f7",
	},
	nord = {
		bg = "#2e3440", bgAlt = "#272c36", text = "#eceff4", muted = "#4c566a", accent = "#88c0d0",
		success = "#a3be8c", error = "#bf616a", warn = "#ebcb8b", info = "#81a1c1",
		border = "#3b4252", selection = "#434c5e", cursor = "#d8dee9", prompt = "#b48ead",
	},
}

local SCHEMES: { string } = { "tokyonight", "gruvbox", "catppuccin", "nord" }

Theme.current = "tokyonight"
Theme.tokens = TOKENS
local listeners: { (name: string) -> () } = {}

--- The list of built-in scheme names.
function Theme.list(): { string }
	return table.clone(SCHEMES)
end

--- Whether a scheme is registered.
function Theme.has(name: string): boolean
	return PALETTES[name] ~= nil
end

--- Registers (or overrides) a scheme. It must define every [[Token]].
function Theme.register(name: string, palette: Palette)
	for _, token in TOKENS do
		if palette[token] == nil then
			error(`theme '{name}' is missing the '{token}' token`, 2)
		end
	end
	if not PALETTES[name] then
		table.insert(SCHEMES, name)
	end
	PALETTES[name] = table.clone(palette)
end

--- Switches the active scheme and notifies every listener (the live recolor).
function Theme:Set(name: string)
	if not PALETTES[name] then
		error(`unknown theme '{name}' (have: {table.concat(SCHEMES, ", ")})`, 2)
	end
	self.current = name
	for _, fn in listeners do
		fn(name)
	end
end

--- The hex string for a token in the active scheme (falls back to `text`).
function Theme:Get(token: string): string
	local palette = PALETTES[self.current]
	return palette[token] or palette.text
end

--- The active palette (a copy).
function Theme:Palette(): Palette
	return table.clone(PALETTES[self.current])
end

--- Subscribes to scheme changes; returns an unsubscribe function.
function Theme:OnChange(fn: (name: string) -> ()): () -> ()
	table.insert(listeners, fn)
	return function()
		local index = table.find(listeners, fn)
		if index then
			table.remove(listeners, index)
		end
	end
end

--- Resolves a token to a `Color3` (Roblox only).
function Theme:Color3(token: string): Color3
	return Color3.fromHex(self:Get(token))
end

return Theme
