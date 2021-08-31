local config      = require 'config'
local defaultlibs = require 'library.defaultlibs'
local define      = require 'proto.define'
local fs          = require 'bee.filesystem'
local furi        = require 'file-uri'
local json        = require 'json'
local util        = require 'utility'

local rojo = {}

rojo.Watch = {}
rojo.RojoProject = {}
rojo.LibraryCache = {}
rojo.DataModel = nil

local librariesTypes = {
    ["Roact"] = {
        textPattern = "Packages up the internals of Roact and exposes a public API for it"
    }
}
local keys = {
    ["$className"] = true,
    ["$path"] = true,
    ["$properties"] = true,
    ["$ignoreUnknownInstances"] = true
}

local function split(str, pat)
    local t = {}
    local fpat = "(.-)" .. pat
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)
    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(t, cap)
        end
        last_end = e+1
        s, e, cap = str:find(fpat, last_end)
    end
    if last_end <= #str then
        cap = str:sub(last_end)
        table.insert(t, cap)
    end
    return t
end

function rojo:scriptClass(filename)
    if filename:match("^.+%.server%.lua$") then
        return "Script"
    elseif filename:match("^.+%.client%.lua$") then
        return "LocalScript"
    elseif filename:match("^.+%.lua$") then
        return "ModuleScript"
    end
end

local function removeLuaExtension(name)
    return name:gsub("%.server%.lua$", ""):gsub("%.client%.lua$", ""):gsub("%.lua$", "")
end

local function inspectModel(model)
    if not model.Children then
        return
    end
    local tree = {}
    pcall(function()
        for _, child in pairs(model.Children) do
            if child.Name and child.ClassName then
                tree[child.Name] = {
                    name = child.Name,
                    type = "type.library",
                    kind = "child",
                    value = {
                        [1] = child.ClassName,
                        type = "type.name",
                        child = inspectModel(child)
                    }
                }
            end
        end
    end)
    return tree
end

local function searchFile(parent, parentPath, filePath)
    local path = fs.current_path() / filePath
    if not path then
        return
    end
    if fs.is_directory(path) then
        parent.value[1] = "Folder"
        for childPath in path:list_directory() do
            local childName = tostring(childPath:filename())
            if rojo:scriptClass(childName) then
                if childName == "init.lua" then
                    parent.value[1] = rojo:scriptClass(childName)
                    parent.value.file = tostring(childPath)
                else
                    local name = removeLuaExtension(childName)
                    parent.value.child[name] = {
                        name = name,
                        type = "type.library",
                        kind = "child",
                        value = {
                            [1] = rojo:scriptClass(childName),
                            type = "type.name",
                            path = parentPath .. "/" .. name,
                            uri = tostring(childPath)
                        }
                    }
                end
            elseif fs.is_directory(childPath) then
                local child = {
                    name = childName,
                    type = "type.library",
                    kind = "child",
                    value = {
                        [1] = "Folder",
                        type = "type.name",
                        path = parentPath .. "/" .. childName,
                        child = {}
                    }
                }
                searchFile(child, child.value.path, filePath .. "/" .. childName)
                parent.value.child[childName] = child
            elseif childName == "init.meta.json" then
                local success, meta = pcall(json.decode, util.loadFile(childPath))
                if success and meta.className then
                    parent.value[1] = meta.className
                end
            elseif childName:match("%.model%.json$") then
                local name = childName:gsub("%.model%.json$", "")
                local success, model = pcall(json.decode, util.loadFile(childPath))
                if success then
                    parent.value.child[name] = {
                        name = name,
                        type = "type.library",
                        kind = "child",
                        value = {
                            [1] = model.ClassName,
                            type = "type.name",
                            path = parentPath .. "/" .. name,
                            child = inspectModel(model)
                        }
                    }
                end
            elseif childName:match("%.txt$") then
                local name = childName:gsub("%.txt$", "")
                parent.value.child[name] = {
                    name = name,
                    type = "type.library",
                    kind = "child",
                    value = {
                        [1] = "StringValue",
                        type = "type.name",
                        path = parentPath .. "/" .. name,
                    }
                }
            elseif childName:match("%.csv$") then
                local name = childName:gsub("%.csv$", "")
                parent.value.child[name] = {
                    name = name,
                    type = "type.library",
                    kind = "child",
                    value = {
                        [1] = "LocalizationTable",
                        type = "type.name",
                        path = parentPath .. "/" .. name,
                    }
                }
            elseif childName:match("%.json$") and not childName:match("%.meta%.json$")  then
                local name = childName:gsub("%.json$", "")
                parent.value.child[name] = {
                    name = name,
                    type = "type.library",
                    kind = "child",
                    value = {
                        [1] = "ModuleScript",
                        type = "type.name",
                        path = parentPath .. "/" .. name,
                    }
                }
            end
        end
    else
        local name = tostring(path:filename())
        if rojo:scriptClass(name) then
            parent.value[1] = rojo:scriptClass(name)
            parent.value.file = tostring(path)
        elseif name:match("%.model%.json$") then
            local success, model = pcall(json.decode, util.loadFile(path))
            if success then
                parent.value[1] =  model.ClassName
                local modelChildren = inspectModel(model)
                if modelChildren then
                    parent.value.child = parent.value.child or {}
                    util.mergeTable(parent.value.child, modelChildren)
                end
            end
        elseif name:match("%.txt$") then
            parent.value[1] = "StringValue"
        elseif name:match("%.csv$") then
            parent.value[1] = "LocalizationTable"
        elseif name:match("%.json$") and not name:match("%.meta%.json$")  then
            parent.value[1] = "ModuleScript"
        end
    end
end

local function normalizePath(path)
    return path:gsub("[/\\]+", "/"):gsub("/$", ""):gsub("^%.%/", "")
end

local function getChildren(parent, name, tree, path)
    if name then
        path = path .. "/" .. name
    end
    local obj = {
        name = name,
        type = "type.library",
        kind = "child",
        value = {
            [1] = "Instance",
            type = "type.name",
            path = path,
            child = {}
        }
    }
    if tree["$path"] then
        local filePath = normalizePath(tree["$path"])
        rojo.Watch[#rojo.Watch+1] = filePath
        searchFile(obj, path, filePath)
    end
    if tree["$className"] then
        obj.value[1] = tree["$className"]
    end
    for _name, child in pairs(tree) do
        if _name:sub(1, 1) ~= "$" then
            getChildren(obj, _name, child, path)
        end
    end
    if name then
        parent.value.child[name] = obj
    else
        parent.value = obj.value
    end
end

function rojo:matchLibrary(filePath)
    if filePath:match("%.spec%.lua$") then
        return nil
    end
    local cache = rojo.LibraryCache[filePath]
    if cache ~= nil then
        if cache == false then
            return nil
        end
        return cache
    end
    local text = util.loadFile(filePath)
    for tp, info in pairs(librariesTypes) do
        if text:match(info.textPattern) then
            rojo.LibraryCache[filePath] = {
                [1] = tp,
                type = "type.name",
                typeAlias = defaultlibs.customType[tp]
            }
            return rojo.LibraryCache[filePath]
        end
    end
    rojo.LibraryCache[filePath] = false
    return nil
end

function rojo:projectChanged(change)
    local projectFileName = config.config.workspace.rojoProjectFile
    if change.uri:match(projectFileName .. "%.project%.json$") then
        return true
    else
        local path = furi.decode(change.uri)
        if path then
            local filename = fs.path(path):filename():string()
            if change.type == define.FileChangeType.Changed
            and filename ~= "init.meta.json"
            and not filename:match("%.model%.json$") then
                return false
            end
            return self:findScriptInProject(change.uri)
        end
    end
end

function rojo:findScriptInProject(uri)
    if not self.RojoProject then
        return true
    end
    for _, path in pairs(self.Watch) do
        if uri:match(path) then
            return true
        end
    end
end

function rojo:updateDatamodel(datamodel)
    self.DataModel = inspectModel(datamodel)
end

function rojo:loadRojoProject()
    self.LibraryCache = {}
    self.RojoProject = {}
    self.Watch = {}
    if config.config.workspace.rojoProjectFile ~= "" then
        local filename = config.config.workspace.rojoProjectFile .. ".project.json"
        if fs.exists(fs.current_path() / filename) then
            local success, project = pcall(json.decode, util.loadFile((fs.current_path() / filename):string()))
            if success and project.tree then
                self.RojoProject = {project}
            else
                return
            end
        end
    else
        for path in fs.current_path():list_directory() do
            if path:string():match("%.project%.json") then
                local success, project = pcall(json.decode, util.loadFile(path:string()))
                if success and project.tree then
                    self.RojoProject[#self.RojoProject+1] = project
                end
            end
        end
    end
    if #self.RojoProject == 0 then
        return
    end
    local mainTree = {}
    for _, project in pairs(self.RojoProject) do
        local tree = {value = {child = {}}}
        getChildren(tree, nil, project.tree, "")
        mainTree = util.mergeTable(mainTree, tree)
    end
    table.sort(self.Watch, function(a, b)
        return #a > #b
    end)
    return mainTree
end

function rojo:searchRojoPaths(paths, tree, parent)
    for name, items in pairs(tree) do
        if not keys[name] then
            if items["$path"] then
                paths[#paths + 1] = {
                    path = parent .. "/" .. name,
                    uri = normalizePath(items["$path"])
                }
            end
            self:searchRojoPaths(paths, items, parent .. "/" .. name)
        end
    end
    return paths
end

function rojo:findScriptByPath(uri)
    if #self.RojoProject == 0 then
        return
    end
    local path = nil
    local rojoPaths = {}
    for _, project in pairs(self.RojoProject) do
        self:searchRojoPaths(rojoPaths, project.tree, "")
    end
    table.sort(rojoPaths, function(a, b)
        return #a.uri > #b.uri
    end)
    for _, info in pairs(rojoPaths) do
        local _, finish = uri:find(info.uri, 1, true)
        if finish then
            path = info.path:sub(2) .. uri:sub(finish + 1)
            break
        end
    end
    if not path then
        return
    end
    local fileName = nil
    for str in path:gmatch(".+/(.+%.lua)$") do
        fileName = str
    end
    if not fileName then
        return
    end
    path = path:sub(1, (#path - #fileName) - 1)
    fileName = removeLuaExtension(fileName)
    if fileName == "init" then
        for str in path:gmatch(".+/(.+)$") do
            fileName = str
        end
        path = path:sub(1, (#path - #fileName) - 1)
    end
    local rbxlibs = require 'library.rbxlibs'
    local current = rbxlibs.global["game"]
    for _, name in pairs(split(path,'[\\/]+')) do
        if current.value.child then
            for _, child in pairs(current.value.child) do
                if child.name == name and rbxlibs.ClassNames[current.value[1]] then
                    current = child
                end
            end
        else
            break
        end
    end
    if current and current.value.child then
        local script = nil
        for _, child in pairs(current.value.child) do
            if child.name == fileName and rbxlibs.ClassNames[current.value[1]] then
                script = child
                break
            end
        end
        if script then
            return script.value
        end
    end
end

function rojo:findPathByScript(script)
    if #self.RojoProject == 0 then
        return
    end
    if not script.path then
        return
    end
    local path = script.path
    local rojoPaths = {}
    for _, project in pairs(self.RojoProject) do
        self:searchRojoPaths(rojoPaths, project.tree, "")
    end
    table.sort(rojoPaths, function(a, b)
        return #a.path > #b.path
    end)
    for _, info in pairs(rojoPaths) do
        local _, finish = path:find(info.path, 1, true)
        if finish then
            path = info.uri .. path:sub(finish + 1)
            break
        end
    end
    path = path:gsub("%/", ".")
    return path
end

return rojo