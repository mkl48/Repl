--- The **structured output model**. Commands never print strings — they emit
--- `Segment`s (styled text runs), grouped into `Line`s, optionally grouped into
--- a `Block` (a table, an ascii art, a status panel). Colors are *semantic
--- tokens* (`"success"`, `"error"`, `"accent"`, `"muted"`…), not `Color3`, so the
--- same output recolors live when the theme changes and stays fully headless.
--- `toText` flattens any node to plain text for logs and no-UI fallbacks.
--- @section Render
--- @client

local Output = {}

--- A styled run of text. `color` is a semantic token resolved by the theme.
export type Segment = {
	text: string,
	color: string?,
	bold: boolean?,
	italic: boolean?,
	underline: boolean?,
	icon: string?, -- a Lucide icon name rendered before the text
}

--- A row of segments. `kind` gives it semantic meaning (and a default color):
--- "plain" | "success" | "error" | "warn" | "info" | "message".
export type Line = {
	class: "Line",
	kind: string,
	segments: { Segment },
}

--- A group of lines with a structural `kind`: "block" | "table" | "ascii" | "status".
export type Block = {
	class: "Block",
	kind: string,
	lines: { Line },
}

export type Node = Line | Block

--- Builds a styled segment. `style` may set color/bold/italic/underline/icon.
function Output.segment(text: string, style: { [string]: any }?): Segment
	local segment: Segment = { text = text }
	if style then
		segment.color = style.color
		segment.bold = style.bold
		segment.italic = style.italic
		segment.underline = style.underline
		segment.icon = style.icon
	end
	return segment
end

-- coerce a string, a segment, or a list of segments into a segment list
local function toSegments(content: string | Segment | { Segment }): { Segment }
	if type(content) == "string" then
		return { Output.segment(content) }
	elseif (content :: any).text ~= nil then
		return { content :: Segment } -- a lone segment
	end
	return content :: { Segment }
end

--- Builds a line of the given `kind` from a string, a segment, or segments.
function Output.line(kind: string, content: string | Segment | { Segment }): Line
	return { class = "Line", kind = kind, segments = toSegments(content) }
end

-- semantic one-liners: each tags the line kind and colors its text to match
local function semantic(kind: string, color: string)
	return function(text: string): Line
		return { class = "Line", kind = kind, segments = { Output.segment(text, { color = color }) } }
	end
end

--- A neutral line.
Output.plain = semantic("plain", "text")
--- A success line (green token).
Output.success = semantic("success", "success")
--- An error line (red token).
Output.error = semantic("error", "error")
--- A warning line (yellow token).
Output.warn = semantic("warn", "warn")
--- An informational line (accent token).
Output.info = semantic("info", "accent")
--- A muted, secondary line.
Output.message = semantic("message", "muted")

--- Groups lines into a block of the given structural `kind`.
function Output.block(kind: string, lines: { Line }): Block
	return { class = "Block", kind = kind, lines = lines }
end

--- Builds a simple text table block from rows of cells (each cell becomes a
--- muted-separated segment run; columns are padded to align).
function Output.table(rows: { { string } }): Block
	-- compute column widths
	local widths: { number } = {}
	for _, row in rows do
		for col, cell in row do
			widths[col] = math.max(widths[col] or 0, #cell)
		end
	end
	local lines: { Line } = {}
	for _, row in rows do
		local segments: { Segment } = {}
		for col, cell in row do
			local padded = cell .. string.rep(" ", (widths[col] or 0) - #cell)
			table.insert(segments, Output.segment(padded))
			if col < #row then
				table.insert(segments, Output.segment("  ", { color = "muted" }))
			end
		end
		table.insert(lines, { class = "Line", kind = "plain", segments = segments })
	end
	return Output.block("table", lines)
end

--- Flattens a line or block to plain text (styling dropped), joining a block's
--- lines with newlines. Icons render as `[name] `.
function Output.toText(node: Node): string
	local function lineText(line: Line): string
		local parts = {}
		for _, seg in line.segments do
			if seg.icon then
				table.insert(parts, `[{seg.icon}] `)
			end
			table.insert(parts, seg.text)
		end
		return table.concat(parts)
	end

	if node.class == "Line" then
		return lineText(node :: Line)
	end
	local out = {}
	for _, line in (node :: Block).lines do
		table.insert(out, lineText(line))
	end
	return table.concat(out, "\n")
end

return Output
