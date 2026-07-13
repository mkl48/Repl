-- Headless module loader for Repl's shell sources.
--
-- The source modules use Roblox-style requires (`require(script.Parent.Token)`).
-- Lune has no `script`, so this loader emulates the instance tree: `src/Shell/
-- init.luau` becomes the "Shell" ModuleScript and every other `src/Shell/*.luau`
-- becomes a child of it, loaded with a custom environment that injects the right
-- `script` handle and a `require` that resolves handles. Standard globals survive.

local luau = require("@lune/luau")
local fs = require("@lune/fs")

local DIR = "src/_Utility/Shell"

local handleMt = {
	__index = function(self, key)
		local kids = rawget(self, "children")
		local kid = kids and kids[key]
		if kid then
			return kid
		end
		error(`Repl loader: '{rawget(self, "Name")}' has no child '{tostring(key)}'`, 2)
	end,
}

local function makeHandle(name: string, file: string)
	return setmetatable({ Name = name, file = file, children = {}, Parent = nil }, handleMt)
end

local shell = makeHandle("Shell", "init")
local srcFolder = setmetatable({ Name = "src", children = { Shell = shell } }, handleMt)
shell.Parent = srcFolder

for _, entry in fs.readDir(DIR) do
	local name = entry:match("^(.+)%.luau$")
	if name and name ~= "init" then
		local child = makeHandle(name, name)
		child.Parent = shell
		shell.children[name] = child
	end
end

local cache: { [any]: any } = {}

local function customRequire(handle)
	if cache[handle] ~= nil then
		return cache[handle]
	end
	local file = rawget(handle, "file")
	local source = fs.readFile(`{DIR}/{file}.luau`)
	local chunk = luau.load(source, {
		debugName = rawget(handle, "Name"),
		environment = { script = handle, require = customRequire },
	})
	local result = chunk()
	cache[handle] = result
	return result
end

local Loader = {}

--- get("Lexer") -> the Lexer module; get("Shell") -> the Shell module (init.luau).
function Loader.get(name: string): any
	if name == "Shell" or name == "init" then
		return customRequire(shell)
	end
	local child = shell.children[name]
	if not child then
		error(`Repl loader: no module '{name}' in {DIR}`, 2)
	end
	return customRequire(child)
end

return Loader
