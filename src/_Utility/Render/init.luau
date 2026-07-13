--- Rendering. The headless [[Output]] model (Segment/Line/Block + a plain-text
--- flattener) lives here; the Fusion terminal renderer that turns those nodes
--- into themed, animated instances joins it later (Studio-only).
--- @section Render
--- @client

local Render = {}

Render.Output = require(script.Output)

return Render
