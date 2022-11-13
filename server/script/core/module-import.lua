local rbxlibs = require("library.rbxlibs")
local config = require("config")
local glob = require("glob")
local furi = require("file-uri")
local util = require("utility")
local guide = require("core.guide")
local calcline = require 'parser.calcline'
local files   = require 'files'
local vm = require("vm")

local rbximports = {}

rbximports.resolveCallback = {}

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
function rbximports.getAbsoluteRequireArg(path)
	local builder = { path[1].name }

	for index, node in ipairs(path) do
		if index ~= 1 then
			if index ~= #path and not canIndexObject(node) then
				return
			end

			table.insert(builder, getSafeIndexer(node.name))
		end
	end

	return table.concat(builder)
end

function rbximports.getAbsoluteRequireArgEdits(path, name, ast, offset)
	local locals = {}
	local skipService = false
	for localName, loc in pairs(guide.getVisibleLocals(ast.ast, offset)) do
		if localName ~= "@fenv" and loc.value then
			for _, def in ipairs(vm.getDefs(loc.value)) do
				if def.type == "type.name" then
					for _, node in ipairs(path) do
						if node.value == def or (rbxlibs.Services[def[1]] and node.value[1] == def[1]) then
							locals[node] = localName
							skipService = true
							break
						end
					end
				end
			end
		end
	end
	local edits = {}
	if not skipService and path[1].value[1] == "DataModel" and rbxlibs.Services[path[2].value[1]] then
		locals[path[2]] = path[2].value[1]
		edits[#edits+1] = rbximports.buildInsertGetService(ast, offset, path[2].value[1])
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
	edits[#edits+1] = rbximports.buildInsertRequire(ast, offset, name, table.concat(builder))
	return edits
end

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

	rbximports.resolveCallback = {}

	local sourcePath = rbximports.findPath(sourceUri)
	local alwaysAbsoluteGlob = getAlwaysAbsoluteGlob()

	local matches = {}
	for _, match in ipairs(rawMatches) do
		-- Never do `require(script)` or equivalent.
		if match.object.uri ~= sourceUri then
			local targetPath = match.path
			match.relativeLuaPath = isRelativePathSupported(match.object.uri, alwaysAbsoluteGlob) and sourcePath and rbximports.findRelativeRequireArg(sourcePath, targetPath) or nil
			match.absoluteLuaPath = isAbsolutePathSupported() and rbximports.getAbsoluteRequireArg(targetPath, ast, offset) or nil

			if match.absoluteLuaPath then
				rbximports.resolveCallback[match.absoluteLuaPath] = function ()
					return {
						changes = {
							[sourceUri] = rbximports.getAbsoluteRequireArgEdits(targetPath, targetName, ast, offset)
						}
					}
				end
			end

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

function rbximports.buildInsertRequire(ast, offset, name, path)
	local minPos
    local firstNode = path:match("^[%w_]+")
    if firstNode ~= "game" and firstNode ~= "script" then
        for localName, loc in pairs(guide.getVisibleLocals(ast.ast, offset)) do
            if localName == firstNode then
                minPos = loc.start
            end
        end
    end
    local importPos = minPos
    guide.eachSourceType(ast.ast, 'callargs', function (source)
        if guide.getSimpleName(source.parent.node) == "require" then
            local parentBlock = guide.getParentBlock(source)
            if offset <= parentBlock.finish and offset >= source.finish and guide.getParentType(source, "local") then
                if parentBlock == ast.ast and source.start > (minPos or 0) then
                    importPos = math.max(importPos or 0, source.start)
                end
            end
        end
    end)

    local start = 1
    if importPos then
        local uri = guide.getUri(ast.ast)
        local text  = files.getText(uri)
        local lines = files.getLines(uri)
        local row = calcline.rowcol(text, importPos)
        start = lines[math.min(row + 1, #lines)].start
    end

    return {
		start   = start,
		finish  = start - 1,
		newText = ('local %s = require(%s)\n'):format(name, path),
	}
end

function rbximports.buildInsertGetService(ast, offset, serviceName)
    local uri = guide.getUri(ast.ast)
    local text  = files.getText(uri)
    local lines = files.getLines(uri)

    local importPositions = {}
    local quotes = '"'
    guide.eachSourceType(ast.ast, 'callargs', function (source)
        if guide.getSimpleName(source.parent.node) == "GetService" then
            local parentBlock = guide.getParentBlock(source)
            if offset <= parentBlock.finish and offset >= source.finish and guide.getParentType(source, "local") then
                for _, arg in ipairs(source) do
                    if arg.type == "string" then
                        quotes = arg[2] or quotes
                        if parentBlock == ast.ast then
                            importPositions[#importPositions+1] = {
                                name = arg[1],
                                pos  = source.start
                            }
                        end
                        break
                    end
                end
            end
        end
    end)

    local pos = 1
    if #importPositions > 0 then
        table.sort(importPositions, function (a, b)
            return a.pos < b.pos
        end)
        for _, info in pairs(importPositions) do
            if serviceName < info.name then
                pos = lines[calcline.rowcol(text, info.pos)].start
                break
            else
                pos = lines[math.min(calcline.rowcol(text, info.pos) + 1, #lines)].start
            end
        end
    end

    return {
		start   = pos,
		finish  = pos - 1,
		newText = ('local %s = game:GetService(%s%s%s)\n'):format(serviceName, quotes, serviceName, quotes:gsub("%[", "]"))
	}
end

return rbximports
