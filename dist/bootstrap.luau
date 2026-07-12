-- Repl bootstrap: paste into the Studio command bar.
-- Fetches and runs the full installer over HTTP (enable Game Settings ->
-- Security -> Allow HTTP Requests). If loadstring is unavailable, install
-- manually by pasting dist/install.luau instead.
local url = "https://raw.githubusercontent.com/mkl48/Repl/master/dist/install.luau"
local ok, result = pcall(function()
	return game:GetService("HttpService"):GetAsync(url)
end)
if not ok then
	warn("Repl bootstrap: HTTP request failed — enable Allow HTTP Requests in Game Settings > Security. " .. tostring(result))
	return
end
local fn, parseError = loadstring(result)
if not fn then
	warn("Repl bootstrap: could not load installer: " .. tostring(parseError))
	return
end
fn()
