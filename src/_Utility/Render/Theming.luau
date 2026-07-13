--- The **theme → Fusion bridge**. [[Theme]] is a plain, headless module; this
--- wraps its active scheme in a Fusion `Value` and hands out `Computed` colors,
--- so any instance property bound with `Theming.color(scope, token)` recolors the
--- instant `Theme:Set` runs. Studio-only (pulls Fusion).
--- @section Render
--- @client

local Fusion = require(script.Parent.Parent.Parent._Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)

local scoped = Fusion.scoped

local Theming = {}

-- one persistent, app-global scope holding the active-scheme state; it lives for
-- the session, so it is intentionally never cleaned up
local root = scoped(Fusion)
local scheme = root:Value(Theme.current)

-- mirror every Theme:Set into the Fusion graph
Theme:OnChange(function(name)
	scheme:set(name)
end)

--- The Fusion `Value` holding the active scheme name (track it in a Computed to
--- react to theme changes).
Theming.scheme = scheme

--- A `Computed` `Color3` for `token` in the active scheme — rebinds live.
function Theming.color(scope: any, token: string): any
	return scope:Computed(function(use)
		use(scheme) -- re-evaluate whenever the scheme changes
		return Color3.fromHex(Theme:Get(token))
	end)
end

--- The current hex value for `token` (non-reactive, for one-off reads).
function Theming.hex(token: string): string
	return Theme:Get(token)
end

return Theming
