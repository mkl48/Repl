--- The **command bar** — the visible surface. A bottom-anchored terminal: a
--- scrolling output area, a prompt + TextBox input with inline **ghost text**, and
--- an **autocomplete popover** driven by the [[Completer]]. Up/Down walk
--- [[History]]; Tab accepts the ghost/top suggestion; Enter submits the line to
--- the injected `submit` callback (the dispatcher, once it exists). Output is
--- drawn by the [[Terminal]] renderer and recolors live with the [[Theme]].
--- Studio-only (pulls Fusion).
--- @section Client
--- @client

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Fusion = require(script.Parent.Parent.Parent._Packages.Fusion)
local Theming = require(script.Parent.Parent.Parent._Utility.Render.Theming)
local Terminal = require(script.Parent.Parent.Parent._Utility.Render.Terminal)
local Output = require(script.Parent.Parent.Parent._Utility.Render.Output)
local Completer = require(script.Parent.Completer)
local History = require(script.Parent.History)

local peek = Fusion.peek
local scoped = Fusion.scoped
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local OnChange = Fusion.OnChange

local Bar = {}
Bar.__index = Bar

export type Config = {
	registry: any, -- a Registry (for completions)
	submit: ((text: string) -> ())?, -- runs a submitted line
	prompt: string?, -- the prompt path, e.g. "Arena/kr3ative/repl"
	parent: Instance?, -- defaults to a fresh ScreenGui in PlayerGui
	activationKey: Enum.KeyCode?, -- default Backquote (`)
}

local FONT = Enum.Font.Code
local TEXT_SIZE = 16
local ROW_HEIGHT = 30
local COMPLETION_HEIGHT = 24

--- Creates and mounts the bar. Returns a bar handle (`:show`/`:hide`/`:toggle`,
--- `:print`, `:printText`, `:destroy`).
function Bar.new(config: Config)
	local self = setmetatable({}, Bar)
	local scope = scoped(Fusion)

	self._scope = scope
	self._registry = config.registry
	self._submit = config.submit
	self._history = History.new()
	self._connections = {} :: { RBXScriptConnection }
	self._prompt = config.prompt or "kr3ative/repl"

	local input = scope:Value("")
	local visible = scope:Value(false)
	self._input = input
	self._visible = visible

	-- reactive completions + ghost, recomputed as the input changes
	local completions = scope:Computed(function(use)
		return Completer.complete(self._registry, use(input))
	end)
	local ghost = scope:Computed(function(use)
		return Completer.ghost(self._registry, use(input))
	end)

	local textBox: TextBox -- captured after creation; used by the helpers below

	local function setInput(text: string)
		input:set(text)
		if textBox then
			textBox.Text = text
			textBox.CursorPosition = #text + 1
		end
	end
	self._setInput = setInput

	local function accept(completion)
		local text = peek(input)
		local before = string.sub(text, 1, completion.replaceStart - 1)
		setInput(before .. completion.text .. " ")
	end

	local function acceptGhost()
		local suffix = peek(ghost)
		if suffix ~= "" then
			setInput(peek(input) .. suffix .. " ")
		else
			local list = peek(completions)
			if list[1] then
				accept(list[1])
			end
		end
	end

	local function submit()
		local text = peek(input)
		if text == "" then
			return
		end
		self._history:add(text)
		-- echo the entered line, prompt-style
		self:print(Output.line("plain", {
			Output.segment(`{self._prompt} `, { color = "prompt" }),
			Output.segment("> ", { color = "muted" }),
			Output.segment(text, { color = "text" }),
		}))
		if self._submit then
			self._submit(text)
		end
		setInput("")
	end
	self._submitLine = submit

	-- ── instances ────────────────────────────────────────────────────────────

	local outputFrame = scope:New "ScrollingFrame" {
		Name = "Output",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -16, 1, -(ROW_HEIGHT + 12)),
		Position = UDim2.fromOffset(8, 4),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theming.color(scope, "muted"),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		[Children] = {
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 2),
			},
		},
	}
	self._outputFrame = outputFrame

	local popover = scope:New "Frame" {
		Name = "Autocomplete",
		BackgroundColor3 = Theming.color(scope, "bgAlt"),
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(0, 320, 0, 0),
		Position = UDim2.new(0, 8, 1, -(ROW_HEIGHT + 4)),
		AnchorPoint = Vector2.new(0, 1),
		Visible = scope:Computed(function(use)
			return #use(completions) > 0 and use(input) ~= ""
		end),
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
			scope:New "UIStroke" { Color = Theming.color(scope, "border"), Thickness = 1 },
			scope:New "UIPadding" {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
			},
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 1),
			},
			scope:ForValues(completions, function(_use, rowScope, completion)
				return rowScope:New "TextButton" {
					Name = "Completion",
					BackgroundColor3 = Theming.color(rowScope, "selection"),
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					Size = UDim2.new(1, 0, 0, COMPLETION_HEIGHT),
					Font = FONT,
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = Theming.color(rowScope, "text"),
					Text = `  {completion.text}`,
					[Children] = {
						rowScope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
						rowScope:New "TextLabel" {
							Name = "Detail",
							BackgroundTransparency = 1,
							Size = UDim2.new(1, -8, 1, 0),
							Font = FONT,
							TextSize = 13,
							TextXAlignment = Enum.TextXAlignment.Right,
							TextColor3 = Theming.color(rowScope, "muted"),
							Text = completion.detail,
						},
					},
					[OnEvent "MouseEnter"] = function()
						-- (hover highlight handled by AutoButtonColor alternative later)
					end,
					[OnEvent "Activated"] = function()
						accept(completion)
						if textBox then
							textBox:CaptureFocus()
						end
					end,
				}
			end),
		},
	}

	local promptLabel = scope:New "TextLabel" {
		Name = "Prompt",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		Font = FONT,
		TextSize = TEXT_SIZE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theming.color(scope, "prompt"),
		Text = `{self._prompt} > `,
	}

	-- ghost label sits *behind* the TextBox; the typed portion is covered exactly
	-- by the TextBox's own text (matching font/size/position), so only the ghost
	-- suffix shows through
	local ghostLabel = scope:New "TextLabel" {
		Name = "Ghost",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Font = FONT,
		TextSize = TEXT_SIZE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theming.color(scope, "muted"),
		ZIndex = 1,
		Text = scope:Computed(function(use)
			local suffix = use(ghost)
			if suffix == "" then
				return ""
			end
			return use(input) .. suffix
		end),
	}

	textBox = scope:New "TextBox" {
		Name = "Input",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Font = FONT,
		TextSize = TEXT_SIZE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theming.color(scope, "text"),
		ClearTextOnFocus = false,
		Text = "",
		PlaceholderText = "type a command…",
		PlaceholderColor3 = Theming.color(scope, "muted"),
		ZIndex = 2,
		[OnChange "Text"] = function(newText)
			input:set(newText)
		end,
		[OnEvent "FocusLost"] = function(enterPressed)
			if enterPressed then
				submit()
				task.defer(function()
					if peek(visible) then
						textBox:CaptureFocus()
					end
				end)
			end
		end,
	}
	self._textBox = textBox

	local inputRow = scope:New "Frame" {
		Name = "InputRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 0, ROW_HEIGHT),
		Position = UDim2.new(0, 8, 1, -(ROW_HEIGHT + 4)),
		AnchorPoint = Vector2.new(0, 1),
		[Children] = {
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			},
			promptLabel,
			scope:New "Frame" {
				Name = "Field",
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 0, 1, 0),
				[Children] = {
					-- fill whatever width the prompt leaves, via flex
					scope:New "UIFlexItem" { FlexMode = Enum.UIFlexMode.Fill },
					ghostLabel,
					textBox,
				},
			},
		},
	}

	local container = scope:New "Frame" {
		Name = "ReplBar",
		BackgroundColor3 = Theming.color(scope, "bg"),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0.4, 0),
		AnchorPoint = Vector2.new(0, 1),
		Position = scope:Spring(
			scope:Computed(function(use)
				return if use(visible) then UDim2.new(0, 0, 1, 0) else UDim2.new(0, 0, 1.4, 0)
			end),
			30,
			1
		),
		[Children] = {
			scope:New "UIStroke" { Color = Theming.color(scope, "border"), Thickness = 1 },
			outputFrame,
			popover,
			inputRow,
		},
	}

	self._gui = scope:New "ScreenGui" {
		Name = "Repl",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = config.parent or (Players.LocalPlayer and Players.LocalPlayer:WaitForChild("PlayerGui")),
		[Children] = { container },
	}

	-- ── keyboard: activation + history + tab ─────────────────────────────────
	local activationKey = config.activationKey or Enum.KeyCode.Backquote
	table.insert(
		self._connections,
		UserInputService.InputBegan:Connect(function(inputObject, processed)
			if inputObject.KeyCode == activationKey then
				self:toggle()
				return
			end
			if processed and not textBox:IsFocused() then
				return
			end
			if not peek(visible) or not textBox:IsFocused() then
				return
			end
			if inputObject.KeyCode == Enum.KeyCode.Up then
				local entry = self._history:up(peek(input))
				if entry then
					setInput(entry)
				end
			elseif inputObject.KeyCode == Enum.KeyCode.Down then
				local entry = self._history:down()
				if entry then
					setInput(entry)
				end
			elseif inputObject.KeyCode == Enum.KeyCode.Tab then
				acceptGhost()
			elseif inputObject.KeyCode == Enum.KeyCode.Escape then
				self:hide()
			end
		end)
	)

	return self
end

--- Appends a rendered [[Output]] node to the terminal.
function Bar:print(node: Output.Node)
	local instance = Terminal.render(self._scope, node)
	instance.Parent = self._outputFrame
	return instance
end

--- Convenience: append a plain text line of the given kind.
function Bar:printText(kind: string, text: string)
	return self:print(Output.line(kind, text))
end

--- Shows the bar and focuses the input.
function Bar:show()
	self._visible:set(true)
	task.defer(function()
		self._textBox:CaptureFocus()
	end)
end

--- Hides the bar and releases focus.
function Bar:hide()
	self._visible:set(false)
	self._textBox:ReleaseFocus()
end

--- Flips visibility.
function Bar:toggle()
	if Fusion.peek(self._visible) then
		self:hide()
	else
		self:show()
	end
end

--- Tears down the bar and all its Fusion state and connections.
function Bar:destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	Fusion.doCleanup(self._scope)
end

return Bar
