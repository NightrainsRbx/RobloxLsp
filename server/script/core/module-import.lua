local rbxlibs = require("library.rbxlibs")
local config = require("config")
local glob = require("glob")
local furi = require("file-uri")
local util = require("utility")
local guide = require("core.guide")
local vm = require("vm")

local rbximports = {}

---@alias PathItem table @ An object from the environment used in a path

---@class Match  @ A matching script
---@field public object table @ The matching object from the environment tree
---@field public path PathItem[] @ The path of objects that lead to this object from the root object we're searching in (typically `game`)

---@class ImportMatch:Match
---@field public relativeLuaPath string | nil @ The argument for require, like `"script.Parent.Example"`
---@field public absoluteLuaPath string | nil @ The argument for require, like `"game.ReplicatedStorage.Example"`

---@param name string @ The script name we're searching for
---@param object table | nil @ The object we're searching under. If nil, this defaults to `game`.
---@param matching table | nil @ Used when called recursively. You can ignore this for external use.
---@param path PathItem[] | nil @ Used when called recursively. You can ignore this for external use.
---@param ignoreGlob table | nil @ An array of glob strings to ignore. Defaults to the `importIgnore` settings.
---@return Match[]
function rbximports.findMatchingScripts(name, object, matching, path, ignoreGlob)
	object = object or rbxlibs.global.game
	matching = matching or {}
	path = path or { object }

	if not ignoreGlob then
		if config.config.suggestedImports.importIgnore[1] then
			ignoreGlob = glob.glob(config.config.suggestedImports.importIgnore, { ignoreCase = false })
		else
			ignoreGlob = function(_)
				return false
			end
		end
	end

	for _, child in pairs(object.value.child) do
		if child.name ~= "Parent" then
			if child.name == name and child.type == "type.library" and child.value[1] == "ModuleScript" then
				if not ignoreGlob(furi.decode(child.value.uri)) then
					local pathCopy = util.shallowCopy(path)
					table.insert(pathCopy, child)

					table.insert(matching, {
						object = child.value,
						path = pathCopy,
					})
				end
			end
			if child.type == "type.library" and child.value.child then
				table.insert(path, child)
				rbximports.findMatchingScripts(name, child, matching, path, ignoreGlob)
				table.remove(path)
			end
		end
	end

	return matching
end

---@param uri string @ The uri of the file we're trying to find an absolute path to
---@param object table @ The object we're searching under. If nil, this defaults to `game`.
---@param path PathItem[] | nil @ Used when called recursively. You can ignore this for external use.
---@return PathItem[] @ The path of objects that lead to this object from the root object we're searching in (typically `game`)
function rbximports.findPath(uri, object, path)
	object = object or rbxlibs.global.game
	path = path or { object }

	for _, child in pairs(object.value.child) do
		if child.name ~= "Parent" then
			if child.type == "type.library" and child.value.uri == uri then
				table.insert(path, child)
				return path
			end

			if child.type == "type.library" and child.value.child then
				table.insert(path, child)
				local result = rbximports.findPath(uri, child, path)
				if result then
					return result
				end
				table.remove(path)
			end
		end
	end
end

local function getSafeIndexer(name)
	if name:match("^%D[%w_]*$") then
		return "." .. name
	else
		return string.format("[%q]", name)
	end
end

local function canIndexObject(object)
	if not config.config.suggestedImports.importScriptChildren then
		if object.value[1]:match("Script$") then
			return false
		end
	end

	return true
end

---@param sourcePath PathItem[] @ The path to the source script we're adding the require statement for
---@param targetPath PathItem[] @ The path to the target script we're adding the require statement for
---@return string | nil @ The text used for the first arg to `require`, for example, `"script.Parent.Example"`. Nil is not possible.
function rbximports.findRelativeRequireArg(sourcePath, targetPath)
	local sourcePathMap = {}
	for index, node in ipairs(sourcePath) do
		-- We only want to use relative paths if they don't go through game or a
		-- service
		local isGame = node == rbxlibs.global.game
		local isChildOfGame = node.value.child and node.value.child.Parent == rbxlibs.global.game
		if not isGame and not isChildOfGame then
			sourcePathMap[node] = index
		end
	end

	local commonAncestor
	local commonAncestorTargetIndex
	for index = #targetPath, 1, -1 do
		local node = targetPath[index]
		if sourcePathMap[node] then
			commonAncestor = node
			commonAncestorTargetIndex = index
			break
		end
	end

	if not commonAncestor then
		return
	end

	local builder = { "script" }

	for _ = #sourcePath - 1, sourcePathMap[commonAncestor], -1 do
		table.insert(builder, ".Parent")
	end

	for index = commonAncestorTargetIndex + 1, #targetPath do
		local node = targetPath[index]

		if index ~= #targetPath and not canIndexObject(node) then
			return
		end

		table.insert(builder, getSafeIndexer(node.name))
	end

	return table.concat(builder)
end

---@param path PathItem[] @ The path to the target script we're adding the require statement for
---@return string @ The text used for the first arg to `require`, for example, `"game.ReplicatedStorage.Example"`
-- function rbximports.getAbsoluteRequireArg(path)
-- 	local builder = { path[1].name }

-- 	for index, node in ipairs(path) do
-- 		if index ~= 1 then
-- 			if index ~= #path and not canIndexObject(node) then
-- 				return
-- 			end

-- 			table.insert(builder, getSafeIndexer(node.name))
-- 		end
-- 	end

-- 	return table.concat(builder)
-- end

function rbximports.checkAbsoluteRequireArg(path)
	for index, node in ipairs(path) do
		if index ~= 1 then
			if index ~= #path and not canIndexObject(node) then
				return false
			end
		end
	end

	return true
end

function rbximports.getAbsoluteRequireArg(path, ast, offset)
	local locals = {}
	for localName, loc in pairs(guide.getVisibleLocals(ast.ast, offset)) do
		if localName ~= "@fenv" then
			for _, def in ipairs(vm.getDefs(loc.value)) do
				if def.type == "type.name" then
					for _, node in ipairs(path) do
						if node.value == def or (rbxlibs.Services[def[1]] and node.value[1] == def[1]) then
							locals[node] = localName
							break
						end
					end
				end
			end
		end
	end
	local builder = {}
	for i = #path, 1, -1 do
		local node = path[i]
		if locals[node] then
			table.insert(builder, 1, locals[node])
			break
		elseif i == 1 then
			table.insert(builder, 1, node.name)
		else
			table.insert(builder, 1, getSafeIndexer(node.name))
		end
	end
	return table.concat(builder)
end

local function isRelativePathSupported(uri, alwaysAbsoluteGlob)
	if config.config.suggestedImports.importPathType == "Absolute Only" then
		return false
	end

	if alwaysAbsoluteGlob(furi.decode(uri)) then
		return false
	end

	return true
end

local function isAbsolutePathSupported()
	return config.config.suggestedImports.importPathType ~= "Relative Only"
end

local function getAlwaysAbsoluteGlob()
	if config.config.suggestedImports.importAlwaysAbsolute[1] then
		return glob.glob(config.config.suggestedImports.importAlwaysAbsolute, { ignoreCase = false })
	else
		return function(_)
			return false
		end
	end
end

---@param sourceUri string @ The source file we're trying to add imports to
---@param targetName string @ The target file name we're trying to add imports for
---@return boolean @ Whether the target has any potential imports usable in the source file
function rbximports.hasPotentialImports(sourceUri, targetName)
	local rawMatches = rbximports.findMatchingScripts(targetName)
	if #rawMatches == 0 then
		return false
	end

	local sourcePath = rbximports.findPath(sourceUri)
	local alwaysAbsoluteGlob = getAlwaysAbsoluteGlob()

	for _, match in ipairs(rawMatches) do
		-- Never do `require(script)` or equivalent.
		if match.object.uri ~= sourceUri then
			local targetPath = match.path
			local relativeLuaPath = isRelativePathSupported(match.object.uri, alwaysAbsoluteGlob) and sourcePath and rbximports.findRelativeRequireArg(sourcePath, targetPath)
			local absoluteLuaPath = isAbsolutePathSupported() and rbximports.checkAbsoluteRequireArg(targetPath)
			-- If the path tries to index into a script and that's disallowed,
			-- it won't have any paths available
			if relativeLuaPath or absoluteLuaPath then
				return true
			end
		end
	end

	return false
end

---@param sourceUri string @ The source file we're trying to add imports to
---@param targetName string @ The target file name we're trying to add imports for
---@return ImportMatch[] @ The potential imports
function rbximports.findPotentialImportsSorted(sourceUri, targetName, ast, offset)
	local rawMatches = rbximports.findMatchingScripts(targetName)
	if #rawMatches == 0 then
		return {}
	end

	local sourcePath = rbximports.findPath(sourceUri)
	local alwaysAbsoluteGlob = getAlwaysAbsoluteGlob()

	local matches = {}
	for _, match in ipairs(rawMatches) do
		-- Never do `require(script)` or equivalent.
		if match.object.uri ~= sourceUri then
			local targetPath = match.path
			match.relativeLuaPath = isRelativePathSupported(match.object.uri, alwaysAbsoluteGlob) and sourcePath and rbximports.findRelativeRequireArg(sourcePath, targetPath) or nil
			match.absoluteLuaPath = isAbsolutePathSupported() and rbximports.getAbsoluteRequireArg(targetPath, ast, offset) or nil
			-- If the path tries to index into a script and that's disallowed,
			-- it won't have any paths available
			if match.relativeLuaPath or match.absoluteLuaPath then
				table.insert(matches, match)
			end
		end
	end

	-- Relative-available matches first, sorted by smallest lua path string,
	-- followed by absolute paths, sorted by smallest lua path string
	table.sort(matches, function(a, b)
		if a.relativeLuaPath and b.relativeLuaPath then
			if #a.relativeLuaPath == #b.relativeLuaPath then
				return a.relativeLuaPath < b.relativeLuaPath
			else
				return #a.relativeLuaPath < #b.relativeLuaPath
			end
		elseif a.relativeLuaPath or b.relativeLuaPath then
			return a.relativeLuaPath ~= nil
		else
			if #a.absoluteLuaPath == #b.absoluteLuaPath then
				return a.absoluteLuaPath < b.absoluteLuaPath
			else
				return #a.absoluteLuaPath < #b.absoluteLuaPath
			end
		end
	end)

	return matches
end

return rbximports
