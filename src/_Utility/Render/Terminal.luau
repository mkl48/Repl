--- The **terminal renderer**: maps the headless [[Output]] tree (Segment/Line/
--- Block) to Fusion instances. A Line becomes one RichText label whose text is a
--- `Computed` — so bold/italic/underline render inline and every segment's
--- [[Theme]] color re-evaluates the moment the scheme changes. A Block becomes a
--- vertically-stacked frame of lines. Studio-only (pulls Fusion).
---
--- Icons (Lucide) are not yet drawn as images — a segment's `icon` is rendered as
--- a `[name]` text marker until the Lucide asset map lands.
--- @section Render
--- @client

local Fusion = require(script.Parent.Parent.Parent._Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)
local Theming = require(script.Parent.Theming)
local Output = require(script.Parent.Output)
local Icons = require(script.Parent.Icons)

local Children = Fusion.Children

local Terminal = {}

local FONT = Enum.Font.Code -- a monospace terminal face
local TEXT_SIZE = 16
local LINE_PADDING = 2

-- RichText needs &, <, > escaped in literal text
local function escape(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

-- one segment → a RichText run, colored by the *current* theme. An icon that
-- resolves to an uploaded image is drawn separately (see Terminal.line); an
-- unmapped icon falls back to a `[name]` text marker so nothing is lost.
local function richSegment(segment: Output.Segment): string
	local body = escape(segment.text)
	if segment.icon and not Icons.resolve(segment.icon) then
		body = `[{escape(segment.icon)}] ` .. body
	end
	if segment.bold then
		body = `<b>{body}</b>`
	end
	if segment.italic then
		body = `<i>{body}</i>`
	end
	if segment.underline then
		body = `<u>{body}</u>`
	end
	local color = Theme:Get(segment.color or "text")
	return `<font color="{color}">{body}</font>`
end

-- the RichText label carrying a line's text
local function textLabel(scope: any, line: Output.Line): TextLabel
	return scope:New "TextLabel" {
		Name = "Text",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		Font = FONT,
		TextSize = TEXT_SIZE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		TextColor3 = Theming.color(scope, "text"), -- fallback for any unfonted run
		Text = scope:Computed(function(use)
			use(Theming.scheme) -- rebuild (and recolor) when the scheme changes
			local parts = {}
			for _, segment in line.segments do
				table.insert(parts, richSegment(segment))
			end
			return table.concat(parts)
		end),
	}
end

--- Renders a single [[Output]] Line. If its first segment carries an icon that
--- resolves to an uploaded image, the line becomes an `[icon][text]` row (the
--- icon tinted to that segment's color); otherwise it's a lone RichText label.
function Terminal.line(scope: any, line: Output.Line): Instance
	local lead = line.segments[1]
	local leadAsset = lead and lead.icon and Icons.resolve(lead.icon)
	if not leadAsset then
		return textLabel(scope, line)
	end
	return scope:New "Frame" {
		Name = `Line_{line.kind}`,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		[Children] = {
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				Padding = UDim.new(0, 6),
			},
			scope:New "ImageLabel" {
				Name = "Icon",
				BackgroundTransparency = 1,
				Image = leadAsset,
				ImageColor3 = Theming.color(scope, lead.color or "text"),
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(TEXT_SIZE, TEXT_SIZE),
				LayoutOrder = 1,
			},
			(function()
				local label = textLabel(scope, line)
				label.LayoutOrder = 2
				-- fill the width the icon leaves
				scope:New "UIFlexItem" { FlexMode = Enum.UIFlexMode.Fill, Parent = label }
				return label
			end)(),
		},
	}
end

--- Renders an [[Output]] Block as a vertically-stacked frame of lines.
function Terminal.block(scope: any, block: Output.Block): Frame
	local lines = {}
	for _, line in block.lines do
		table.insert(lines, Terminal.line(scope, line))
	end
	return scope:New "Frame" {
		Name = `Block_{block.kind}`,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		[Children] = {
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, LINE_PADDING),
			},
			lines,
		},
	}
end

--- Renders any [[Output]] node (Line or Block) to an instance.
function Terminal.render(scope: any, node: Output.Node): Instance
	if node.class == "Block" then
		return Terminal.block(scope, node :: Output.Block)
	end
	return Terminal.line(scope, node :: Output.Line)
end

return Terminal
