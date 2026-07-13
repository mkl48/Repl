-- Headless module loader for Repl's sources.
--
-- The source modules use Roblox-style requires (`require(script.Parent.Token)`,
-- `require(script._Utility.Shell)`). Lune has no `script`, so this loader
-- emulates the whole `src` instance tree: a folder with an init.lua(u) becomes a
-- ModuleScript with children; every other .lua(u) becomes a ModuleScript; other
-- folders become Folders. Each module loads with a custom environment injecting
-- the right `script` handle and a `require` that resolves handles.

local luau = require("@lune/luau")
local fs = require("@lune/fs")

local ROOT_DIR = "src"
local ROOT_NAME = "Repl"

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

local function findInit(dir: string): string?
	for _, name in { "init.lua", "init.luau" } do
		if fs.isFile(dir .. "/" .. name) then
			return dir .. "/" .. name
		end
	end
	return nil
end

-- build a handle tree for `dir`. `file` is the source path if this node is a
-- ModuleScript (a folder's init, or a leaf .luau), else nil (a plain Folder).
local function build(dir: string, name: string, file: string?)
	local handle = setmetatable({ Name = name, file = file, children = {}, Parent = nil }, handleMt)
	local names = fs.readDir(dir)
	table.sort(names)
	for _, entry in names do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			local child = build(full, entry, findInit(full))
			child.Parent = handle
			handle.children[entry] = child
		else
			local modName = entry:match("^(.+)%.luau?$")
			if modName and modName ~= "init" then
				local child = setmetatable(
					{ Name = modName, file = full, children = {}, Parent = handle },
					handleMt
				)
				handle.children[modName] = child
			end
		end
	end
	return handle
end

local root = build(ROOT_DIR, ROOT_NAME, findInit(ROOT_DIR))

local cache: { [any]: any } = {}

local function customRequire(handle)
	if cache[handle] ~= nil then
		return cache[handle]
	end
	local file = rawget(handle, "file")
	if not file then
		error(`Repl loader: '{rawget(handle, "Name")}' is a Folder, not a ModuleScript`, 2)
	end
	local chunk = luau.load(fs.readFile(file), {
		debugName = rawget(handle, "Name"),
		environment = { script = handle, require = customRequire },
	})
	local result = chunk()
	cache[handle] = result
	return result
end

-- depth-first search for a module handle by Name (names are unique in Repl)
local function findByName(handle, name)
	if rawget(handle, "Name") == name and rawget(handle, "file") then
		return handle
	end
	for _, child in rawget(handle, "children") do
		local found = findByName(child, name)
		if found then
			return found
		end
	end
	return nil
end

local Loader = {}
Loader.root = root

--- get("Lexer") -> the Lexer module, found by name anywhere in the tree.
function Loader.get(name: string): any
	local handle = findByName(root, name)
	if not handle then
		error(`Repl loader: no module named '{name}' under {ROOT_DIR}`, 2)
	end
	return customRequire(handle)
end

return Loader
