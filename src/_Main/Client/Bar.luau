--- The **command bar** — the visible surface. A bottom-anchored terminal: a
--- scrolling output area, a prompt + TextBox input with a custom **block cursor**
--- and inline **ghost text**, and an **autocomplete popover** with a highlighted,
--- arrow-cyclable selection. While the bar is focused it takes over input —
--- character movement, shift-lock, and the backpack hotkey are suppressed so a
--- keystroke never leaks to the game. Enter submits to the injected `submit`
--- callback; Ctrl dismisses the suggestions; Backquote toggles; Escape hides.
--- Output is drawn by the [[Terminal]] renderer and recolors live with the
--- [[Theme]]. Exposes dev-facing state (`Focused`, `Visible`) and events
--- (`Opened`, `Closed`, `FocusChanged`, `Submitted`). Studio-only (pulls Fusion).
--- @section Client
--- @client

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local TextService = game:GetService("TextService")

local Fusion = require(script.Parent.Parent.Parent._Packages.Fusion)
local Theming = require(script.Parent.Parent.Parent._Utility.Render.Theming)
local Terminal = require(script.Parent.Parent.Parent._Utility.Render.Terminal)
local Output = require(script.Parent.Parent.Parent._Utility.Render.Output)
local Signal = require(script.Parent.Parent.Parent._Utility.Signal)
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
	activationKeys: { Enum.KeyCode }?, -- default { Backquote }
	cursorStyle: ("block" | "line" | "underline")?, -- default "block"
}

local FONT = Enum.Font.Code
local TEXT_SIZE = 16
local ROW_HEIGHT = 30
local COMPLETION_HEIGHT = 24
local BLINK_PERIOD = 0.53

-- width of one monospace character in the terminal font (computed once)
local function charWidth(): number
	local size = TextService:GetTextSize("M", TEXT_SIZE, FONT, Vector2.new(1e6, 1e6))
	return size.X
end

--- Creates and mounts the bar. Returns a bar handle.
function Bar.new(config: Config)
	local self = setmetatable({}, Bar)
	local scope = scoped(Fusion)

	self._scope = scope
	self._registry = config.registry
	self._submit = config.submit
	self._history = History.new()
	self._connections = {} :: { RBXScriptConnection }
	self._prompt = config.prompt or "kr3ative/repl"
	self._activationKeys = config.activationKeys or { Enum.KeyCode.Backquote }
	self._cursorStyle = config.cursorStyle or "block"
	self._suppressed = false
	self._restore = {} -- saved player settings while focused

	-- ── dev-facing state + events ────────────────────────────────────────────
	self.Opened = Signal.new()
	self.Closed = Signal.new()
	self.FocusChanged = Signal.new() -- fires (isFocused: boolean)
	self.Submitted = Signal.new() -- fires (line: string)

	local input = scope:Value("")
	local visible = scope:Value(false)
	local focused = scope:Value(false)
	local selected = scope:Value(1) -- 1-based index into the completion list
	local dismissed = scope:Value(false) -- Ctrl hides the popover until the next edit
	local cursorPos = scope:Value(1)
	local cursorOn = scope:Value(true) -- blink state
	self._input, self._visible, self._focused = input, visible, focused
	self._selected, self._dismissed = selected, dismissed

	-- reactive completions + ghost
	local completions = scope:Computed(function(use)
		return Completer.complete(self._registry, use(input))
	end)
	local ghost = scope:Computed(function(use)
		return Completer.ghost(self._registry, use(input))
	end)
	local popoverOpen = scope:Computed(function(use)
		return use(focused) and use(input) ~= "" and not use(dismissed) and #use(completions) > 0
	end)
	self._completions = completions
	self._popoverOpen = popoverOpen

	local textBox: TextBox

	local function setInput(text: string)
		input:set(text)
		dismissed:set(false)
		selected:set(1)
		if textBox then
			textBox.Text = text
			textBox.CursorPosition = #text + 1
		end
	end
	self._setInput = setInput

	local function acceptCompletion(completion)
		local text = peek(input)
		local before = string.sub(text, 1, completion.replaceStart - 1)
		setInput(before .. completion.text .. " ")
	end

	local function acceptSelected()
		if peek(popoverOpen) then
			local list = peek(completions)
			acceptCompletion(list[peek(selected)] or list[1])
			return
		end
		local suffix = peek(ghost)
		if suffix ~= "" then
			setInput(peek(input) .. suffix .. " ")
		end
	end

	local function moveSelection(delta: number)
		local list = peek(completions)
		if #list == 0 then
			return
		end
		local next = peek(selected) + delta
		if next < 1 then
			next = #list
		elseif next > #list then
			next = 1
		end
		selected:set(next)
	end

	local function submit()
		local text = peek(input)
		if text == "" then
			return
		end
		self._history:add(text)
		self:print(Output.line("plain", {
			Output.segment(`{self._prompt} `, { color = "prompt" }),
			Output.segment("> ", { color = "muted" }),
			Output.segment(text, { color = "text" }),
		}))
		self.Submitted:Fire(text)
		if self._submit then
			self._submit(text)
		end
		setInput("")
	end
	self._submitLine = submit

	-- ── output area ──────────────────────────────────────────────────────────
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

	-- ── autocomplete popover (square, to match the terminal) ─────────────────
	local popover = scope:New "Frame" {
		Name = "Autocomplete",
		BackgroundColor3 = Theming.color(scope, "bgAlt"),
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(0, 340, 0, 0),
		Position = UDim2.new(0, 8, 1, -(ROW_HEIGHT + 6)),
		AnchorPoint = Vector2.new(0, 1),
		Visible = popoverOpen,
		[Children] = {
			scope:New "UIStroke" { Color = Theming.color(scope, "border"), Thickness = 1 },
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			scope:ForPairs(completions, function(_use, rowScope, index, completion)
				local row = rowScope:New "TextButton" {
					Name = "Completion",
					LayoutOrder = index,
					BackgroundColor3 = Theming.color(rowScope, "selection"),
					-- highlight the indexed row; others are transparent
					BackgroundTransparency = rowScope:Computed(function(use)
						return if use(selected) == index then 0 else 1
					end),
					AutoButtonColor = false,
					Size = UDim2.new(1, 0, 0, COMPLETION_HEIGHT),
					Font = FONT,
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = rowScope:Computed(function(use)
						return Color3.fromHex(Theming.hex(if use(selected) == index then "text" else "muted"))
					end),
					Text = `  {completion.text}`,
					[Children] = {
						rowScope:New "UIPadding" {
							PaddingLeft = UDim.new(0, 6),
							PaddingRight = UDim.new(0, 6),
						},
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
						selected:set(index)
					end,
					[OnEvent "Activated"] = function()
						acceptCompletion(completion)
						if textBox then
							textBox:CaptureFocus()
						end
					end,
				}
				return index, row
			end),
		},
	}

	-- ── input row: prompt + field (ghost, textbox, cursor) ───────────────────
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
			if suffix == "" or use(popoverOpen) then
				return "" -- don't ghost while the popover is showing a selection
			end
			return use(input) .. suffix
		end),
	}

	-- custom terminal cursor (block by default), positioned at the caret
	local cw = charWidth()
	local cursor = scope:New "Frame" {
		Name = "Cursor",
		BorderSizePixel = 0,
		BackgroundColor3 = Theming.color(scope, "cursor"),
		BackgroundTransparency = scope:Computed(function(use)
			return if use(focused) and use(cursorOn) then 0.35 else 1
		end),
		ZIndex = 3,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = scope:Computed(function(use)
			return UDim2.new(0, (use(cursorPos) - 1) * cw, 0.5, 0)
		end),
		Size = (function()
			if self._cursorStyle == "line" then
				return UDim2.new(0, 2, 0, TEXT_SIZE + 2)
			elseif self._cursorStyle == "underline" then
				return UDim2.new(0, cw, 0, 2)
			end
			return UDim2.new(0, cw, 0, TEXT_SIZE + 2) -- block
		end)(),
	}
	if self._cursorStyle == "underline" then
		cursor.AnchorPoint = Vector2.new(0, 1)
		cursor.Position = scope:Computed(function(use)
			return UDim2.new(0, (use(cursorPos) - 1) * cw, 1, -2)
		end)
	end

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
			dismissed:set(false)
			selected:set(1)
			cursorPos:set((textBox and textBox.CursorPosition) or (#newText + 1))
		end,
		[OnChange "CursorPosition"] = function(pos)
			if pos and pos > 0 then
				cursorPos:set(pos)
			end
		end,
		[OnEvent "Focused"] = function()
			focused:set(true)
			self:_suppressGameInput(true)
			self.FocusChanged:Fire(true)
		end,
		[OnEvent "FocusLost"] = function(enterPressed)
			if enterPressed then
				submit()
				task.defer(function()
					if peek(visible) then
						textBox:CaptureFocus()
					end
				end)
			else
				focused:set(false)
				self:_suppressGameInput(false)
				self.FocusChanged:Fire(false)
			end
		end,
	}
	self._textBox = textBox

	local inputRow = scope:New "Frame" {
		Name = "InputRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 0, ROW_HEIGHT),
		Position = UDim2.new(0, 8, 1, -6),
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
					scope:New "UIFlexItem" { FlexMode = Enum.UIFlexMode.Fill },
					ghostLabel,
					cursor,
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
				return if use(visible) then UDim2.new(0, 0, 1, 0) else UDim2.new(0, 0, 1.45, 0)
			end),
			28,
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

	-- blink the cursor
	self._blink = task.spawn(function()
		while true do
			task.wait(BLINK_PERIOD)
			cursorOn:set(not peek(cursorOn))
		end
	end)

	-- ── activation key (sunk via CAS so ` doesn't also open the backpack) ─────
	ContextActionService:BindAction("ReplToggle", function(_, state)
		if state == Enum.UserInputState.Begin then
			self:toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(self._activationKeys))

	-- ── in-terminal keys (only act while open + focused) ─────────────────────
	table.insert(
		self._connections,
		UserInputService.InputBegan:Connect(function(inputObject)
			if not peek(visible) or not textBox:IsFocused() then
				return
			end
			local key = inputObject.KeyCode
			if key == Enum.KeyCode.Up then
				if peek(popoverOpen) then
					moveSelection(-1)
				else
					local entry = self._history:up(peek(input))
					if entry then
						setInput(entry)
					end
				end
			elseif key == Enum.KeyCode.Down then
				if peek(popoverOpen) then
					moveSelection(1)
				else
					local entry = self._history:down()
					if entry then
						setInput(entry)
					end
				end
			elseif key == Enum.KeyCode.Tab then
				acceptSelected()
			elseif key == Enum.KeyCode.Escape then
				self:hide()
			elseif key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.RightControl then
				dismissed:set(true)
			end
		end)
	)

	return self
end

-- suppress/restore character movement, shift-lock, and the backpack hotkey while
-- the terminal has focus, so keystrokes never leak to the game
function Bar:_suppressGameInput(on: boolean)
	if on == self._suppressed then
		return
	end
	self._suppressed = on
	local player = Players.LocalPlayer
	if not player then
		return
	end

	if on then
		-- character controls
		pcall(function()
			local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")) :: any
			self._controls = playerModule:GetControls()
			self._controls:Disable()
		end)
		-- shift lock
		self._restore.mouseLock = player.DevEnableMouseLock
		pcall(function()
			player.DevEnableMouseLock = false
		end)
		-- backpack hotkey / gui
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
	else
		if self._controls then
			pcall(function()
				self._controls:Enable()
			end)
		end
		pcall(function()
			player.DevEnableMouseLock = self._restore.mouseLock
		end)
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
		end)
	end
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

--- Whether the bar is currently open.
function Bar:IsOpen(): boolean
	return Fusion.peek(self._visible)
end

--- Whether the input is currently focused.
function Bar:IsFocused(): boolean
	return Fusion.peek(self._focused)
end

--- Shows the bar and focuses the input.
function Bar:show()
	if self:IsOpen() then
		return
	end
	self._visible:set(true)
	self.Opened:Fire()
	task.defer(function()
		self._textBox:CaptureFocus()
	end)
end

--- Hides the bar and releases focus.
function Bar:hide()
	if not self:IsOpen() then
		return
	end
	self._visible:set(false)
	self._textBox:ReleaseFocus()
	self:_suppressGameInput(false)
	self.Closed:Fire()
end

--- Flips visibility.
function Bar:toggle()
	if self:IsOpen() then
		self:hide()
	else
		self:show()
	end
end

--- Tears down the bar and all its state, connections, and input overrides.
function Bar:destroy()
	self:_suppressGameInput(false)
	if self._blink then
		task.cancel(self._blink)
	end
	pcall(function()
		ContextActionService:UnbindAction("ReplToggle")
	end)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self.Opened:DisconnectAll()
	self.Closed:DisconnectAll()
	self.FocusChanged:DisconnectAll()
	self.Submitted:DisconnectAll()
	Fusion.doCleanup(self._scope)
end

return Bar
