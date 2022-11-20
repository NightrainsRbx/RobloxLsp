local config      = require 'config'
local defaultlibs = require 'library.defaultlibs'
local define      = require 'proto.define'
local fs          = require 'bee.filesystem'
local furi        = require 'file-uri'
local json        = require 'json'
local util        = require 'utility'
local platform    = require 'bee.platform'
local sp          = require 'bee.subprocess'

local rojo = {}

rojo.LibraryCache = {}
rojo.DataModel = nil
rojo.Scripts = {}
rojo.SourceMap = {}

local librariesTypes = {
    ["Roact"] = {
        textPattern = "%-%-%[%[%s+Packages up the internals of Roact and exposes a public API for it%."
    },
    ["Rodux"] = {
        textPattern = "require%(script%.Store%).-require%(script%.createReducer%).-require%(script%.combineReducers%)"
    },
    ["RoactRodux"] = {
        textPattern = "return %{%s+StoreProvider %= StoreProvider%,.-connect %= connect.-%}%s*$"
    },
    -- ["Promise.Static"] = {
    --     textPattern = "%-%-%[%[%s+An implementation of Promises similar to Promise%/A%+%."
    -- },
    -- ["Fusion"] = {
    --     textPattern = "^%s*%-%-%[%[%s*The entry point for the Fusion library%."
    -- }
}

function rojo:scriptClass(filename)
    if filename:match("^.+%.server%.lua[u]?$") then
        return "Script"
    elseif filename:match("^.+%.client%.lua[u]?$") then
        return "LocalScript"
    elseif filename:match("^.+%.lua[u]?$") then
        return "ModuleScript"
    end
end

local function removeLuaExtension(name)
    return name:gsub("%.server%.lua[u]?$", ""):gsub("%.client%.lua[u]?$", ""):gsub("%.lua[u]?$", "")
end

local function normalizePath(path)
    return path:gsub("[/\\]+", "/"):gsub("/$", ""):gsub("^%.%/", "")
end

local function isValidPath(path)
    if type(path) ~= "string" then
        return false
    end
    if normalizePath(path):match("^%/?[%w_]") then
        return true
    end
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

function rojo.searchFile(parent, filePath)
    local path = fs.current_path() / filePath
    if not path then
        return
    end
    if fs.is_directory(path) then
        parent.value[1] = "Folder"
        if fs.exists(path / "default.project.json") then
            local success, project = pcall(json.decode, util.loadFile(path / "default.project.json"))
            if success and project.tree then
                local ws = require("workspace")
                local relativePath = normalizePath(ws.getRelativePath(furi.encode(path:string()))) .. "/"
                local tree = {value = {child = {}}}
                rojo.getChildren(tree, nil, project.tree, relativePath)
                parent.value = tree.value
                if project.name then
                    parent.name = project.name
                end
            end
            return
        end
        for childPath in fs.pairs(path) do
            local childName = tostring(childPath:filename())
            if rojo:scriptClass(childName) then
                local name = removeLuaExtension(childName)
                if name == "init" then
                    parent.value[1] = rojo:scriptClass(childName)
                    parent.value.uri = furi.encode(childPath:string())
                    rojo.Scripts[parent.value.uri] = parent.value
                else
                    local child = {
                        name = name,
                        type = "type.library",
                        kind = "child",
                        value = {
                            [1] = rojo:scriptClass(childName),
                            type = "type.name",
                            uri = furi.encode(childPath:string())
                        }
                    }
                    parent.value.child[name] = child
                    rojo.Scripts[child.value.uri] = child.value
                end
            elseif fs.is_directory(childPath) then
                local child = {
                    name = childName,
                    type = "type.library",
                    kind = "child",
                    value = {
                        [1] = "Folder",
                        type = "type.name",
                        child = {}
                    }
                }
                rojo.searchFile(child, filePath .. "/" .. childName)
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
                    }
                }
            end
        end
    else
        local name = tostring(path:filename())
        if rojo:scriptClass(name) then
            parent.value[1] = rojo:scriptClass(name)
            parent.value.uri = furi.encode(path:string())
            rojo.Scripts[parent.value.uri] = parent.value
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
        elseif name:match("%.project%.json$") then
            local success, project = pcall(json.decode, util.loadFile(path))
            if success and project.tree then
                local ws = require("workspace")
                local relativePath = normalizePath(ws.getRelativePath(furi.encode(path:string():sub(1, #path:string() - #name)))) .. "/"
                local tree = {value = {child = {}}}
                rojo.getChildren(tree, nil, project.tree, relativePath)
                parent.value = tree.value
                if project.name then
                    parent.name = project.name
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

function rojo.getChildren(parent, name, tree, path)
    local obj = {
        name = name,
        type = "type.library",
        kind = "child",
        value = {
            [1] = "Instance",
            type = "type.name",
            child = {}
        }
    }
    if tree["$path"] and isValidPath(tree["$path"]) then
        local filePath = path .. normalizePath(tree["$path"])
        rojo.searchFile(obj, filePath)
    end
    if tree["$className"] then
        obj.value[1] = tree["$className"]
    else
        obj.noClassName = true
    end
    for _name, child in pairs(tree) do
        if _name:sub(1, 1) ~= "$" then
            rojo.getChildren(obj, _name, child, path)
        end
    end
    if name then
        parent.value.child[name] = obj
    else
        parent.value = obj.value
    end
end

function rojo:matchLibrary(uri)
    if not config.config.intelliSense.autoDetectLibraries then
        return
    end
    if uri:match("%.spec%.lua[u]?$") then
        return nil
    end
    local cache = rojo.LibraryCache[uri]
    if cache ~= nil then
        if cache == false then
            return nil
        end
        return cache
    end
    local success, text = pcall(util.loadFile, furi.decode(uri))
    if success then
        for tp, info in pairs(librariesTypes) do
            if text:match(info.textPattern) then
                rojo.LibraryCache[uri] = {
                    [1] = tp,
                    type = "type.name",
                    typeAlias = defaultlibs.customType[tp]
                }
                return rojo.LibraryCache[uri]
            end
        end
    end
    rojo.LibraryCache[uri] = false
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
            and not filename:match("%.meta%.json$")
            and not filename:match("%.model%.json$")
            and not filename:match("%.project%.json$") then
                return false
            end
            return true
        end
    end
end

function rojo:hasFileInProject(uri)
    return self.Scripts[uri]
end

function rojo:parseDatamodel()
    if self.DataModel then
        return inspectModel(self.DataModel)
    end
end

function rojo:getSourceMap(sourceMap, node, path)
    if not node.value.child then
        return sourceMap
    end
    for _, child in pairs(node.value.child) do
        local path = path .. child.name
        if child.value.uri then
            sourceMap[path] = furi.decode(child.value.uri)
        end
        rojo:getSourceMap(sourceMap, child, path .. ".")
    end
    return sourceMap
end

local scriptClasses = {
    ["Script"] = true,
    ["LocalScript"] = true,
    ["ModuleScript"] = true
}

function rojo:buildInstanceTree(tree)
    local node = {
        type = "type.library",
        name = tree.name,
        kind = "child",
        value = {
            type = "type.name",
            [1] = tree.className
        }
    }
    if tree.filePaths and scriptClasses[tree.className] then
        local ws = require("workspace")
        for _, path in ipairs(tree.filePaths) do
            if path:match("%.lua[u]?$") then
                node.value.uri = furi.encode(ws.getAbsolutePath(path))
                self.Scripts[node.value.uri] = node.value
            end
        end
    end
    if tree.children then
        node.value.child = {}
        for _, child in ipairs(tree.children) do
            node.value.child[child.name] = self:buildInstanceTree(child)
        end
    end
    return node
end

function rojo:getRojoPath()
    if config.config.workspace.rojoExecutablePath ~= "" then
        return config.config.workspace.rojoExecutablePath
    end
    if self.RojoPath then
        return self.RojoPath
    end
    if platform.OS == "Windows" then
        for _, path in ipairs(util.split(os.getenv("PATH"), ";")) do
            path = fs.path(path) / "rojo.exe"
            if fs.exists(path) then
                self.RojoPath = path
                return path
            end
        end
    end
    return "rojo"
end

function rojo:parseProject(projectPath, forceDisable)
    if config.config.workspace.useRojoSourcemap and not forceDisable then
        local success, sourceMap = pcall(function()
            local ws = require("workspace")
            local projectPath = ws.getRelativePath(furi.encode(projectPath:string()))
            local rojoPath = self:getRojoPath()
            local process = assert(sp.spawn {
                rojoPath,
                "sourcemap",
                projectPath,
                "--include-non-scripts",
                console = "disable",
                stdin = false,
                stdout = true,
                stderr = true
            })
            local sourceMap = process.stdout:read("a")
            if sourceMap == "" then
                error(process.stderr:read("a"))
            end
            return json.decode(sourceMap)
        end)
        if success and sourceMap then
            return {
                value = self:buildInstanceTree(sourceMap).value
            }
        end
        -- local proto = require("proto.proto")
        -- proto.notify('window/showMessage', {
        --     type    = define.MessageType.Warning,
        --     message = 'Roblox LSP: Could not run rojo executable at "'
        --         .. (config.config.workspace.rojoExecutablePath ~= ""
        --         and config.config.workspace.rojoExecutablePath
        --         or "PATH") .. '", using project file. (' .. tostring(sourceMap):match("(.-)%s*$") .. ")"
        -- })
        return self:parseProject(projectPath, true)
    else
        local success, project = pcall(json.decode, util.loadFile(projectPath:string()))
        if success and project.tree then
            local tree = {value = {child = {}}}
            rojo.getChildren(tree, nil, project.tree, "")
            return tree
        end
    end
end

function rojo:loadRojoProject()
    self.LibraryCache = {}
    self.Scripts = {}
    self.SourceMap = {}
    local rojoProjects = {}
    if config.config.workspace.rojoProjectFile ~= "" then
        local filename = config.config.workspace.rojoProjectFile .. ".project.json"
        if fs.exists(fs.current_path() / filename) then
            rojoProjects[#rojoProjects+1] = self:parseProject(fs.current_path() / filename)
        else
            local proto = require("proto.proto")
            proto.notify('window/showMessage', {
                type    = define.MessageType.Warning,
                message = 'Roblox LSP: Could not find rojo project at ' .. (fs.current_path() / filename):string()
            })
        end
    else
        for path in fs.pairs(fs.current_path()) do
            if path:string():match("%.project%.json") then
                rojoProjects[#rojoProjects+1] = self:parseProject(path)
            end
        end
    end
    if #rojoProjects == 0 then
        return
    end
    local mainTree = {}
    for _, tree in pairs(rojoProjects) do
        mainTree = util.mergeTable(tree, mainTree)
    end
    if mainTree.value[1] == "DataModel" then
        for _, child in pairs(mainTree.value.child) do
            if child.noClassName then
                child.value[1] = child.name
            end
        end
        local StarterPlayer = mainTree.value.child.StarterPlayer
        if StarterPlayer then
            for _, child in pairs(StarterPlayer.value.child) do
                if child.noClassName then
                    child.value[1] = child.name
                end
            end
        end
    end
    self.SourceMap = self:getSourceMap({}, mainTree, "")
    return mainTree
end

return rojo