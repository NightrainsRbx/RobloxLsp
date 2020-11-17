local json = require 'json'
local fs = require 'bee.filesystem'
local uric = require 'uri'
local config = require 'config'

local rojo = {}

rojo.Watch = {}
rojo.RojoProject = {}

local function readFile(path)
    local file = io.open(tostring(path))
    local contents = file:read("*a")
    file:close()
    return contents
end

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

local function scriptClass(filename)
    if filename:match("^.+%.server%.lua$") then
        return "Script"
    elseif filename:match("^.+%.client%.lua$") then
        return "LocalScript"
    elseif filename:match("^.+%.lua$") then
        return "ModuleScript"
    end
end

local function isValidName(name)
    return true--name:match("^[%a_][%w_]*$")
end

local function removeLuaExtension(name)
    return name:gsub("%.server%.lua", ""):gsub("%.client%.lua", ""):gsub("%.lua", "")
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
                    className = child.ClassName,
                    children = inspectModel(child)
                }
            end
        end
    end)
    return tree
end

local function searchFiles(parentPath, tree)
    if type(parentPath) == "string" then
        local current = fs.current_path()
        for _, name in pairs(split(parentPath,'[\\/]+')) do
            if fs.exists(current / name) then
                current = current / name
            else
                current = nil
                break
            end
        end
        parentPath = current
    end
    if not parentPath then
        return
    end
    if fs.is_directory(parentPath) then
        for path in parentPath:list_directory() do
            local name = tostring(path:filename())
            if fs.is_directory(path) then
                if not isValidName(name) then
                    goto CONTINUE
                end
                local child = {
                    className = "Folder",
                    children = {}
                }
                if fs.exists(path / "init.meta.json") then
                    local success, meta = pcall(json.decode, readFile(path / "init.meta.json"))
                    if success and meta.className then
                        child.className = meta.className
                    end
                end
                for _, init in pairs{"init.lua", "init.server.lua", "init.client.lua"} do
                    if fs.exists(path / init) then
                        child.className = scriptClass(tostring((path / init):filename()))
                        break
                    end
                end
                tree.children[name] = child
                searchFiles(path, child)
            else
                if name == "init.meta.json" then
                    local success, meta = pcall(json.decode, readFile(path))
                    if success and meta.className then
                        tree.className = meta.className
                    end
                elseif scriptClass(name) then
                    if name:sub(1, 4) ~= "init" then
                        local className = scriptClass(name)
                        name = removeLuaExtension(name)
                        if not isValidName(name) then
                            goto CONTINUE
                        end
                        tree.children[name] = {
                            className = className
                        }
                    end
                elseif name:match("%.model%.json$") then
                    name = name:gsub("%.model%.json$", "")
                    if not isValidName(name) then
                        goto CONTINUE
                    end
                    local success, model = pcall(json.decode, readFile(path))
                    if success then
                        tree.children[name] = {
                            className = model.ClassName,
                            children = inspectModel(model)
                        }
                    end
                elseif name:match("%.txt$") then
                    name = name:gsub("%.txt$", "")
                    if not isValidName(name) then
                        goto CONTINUE
                    end
                    tree.children[name] = {
                        className = "StringValue"
                    }
                end
            end
            ::CONTINUE::
        end
    else
        local name = tostring(parentPath:filename())
        if name:match("%.model%.json$") then
            name = name:gsub("%.model%.json$", "")
            if not isValidName(name) then
                return
            end
            local success, model = pcall(json.decode, readFile(parentPath))
            if success then
                tree.children = tree.children or {}
                table.merge(tree.children, inspectModel(model))
            end
        end
    end
end

local function getChildren(parent, tree)
    for name, children in pairs(parent) do
        if not keys[name] and isValidName(name) then
            local child = {
                className = children["$className"] or "Instance",
                children = {}
            }
            tree.children[name] = child
            getChildren(children, child)
        elseif name == "$path" then
            rojo.Watch[#rojo.Watch+1] = children:gsub("[/\\]+", "/")
            searchFiles(children, tree)
        end
    end
end

function rojo:projectChanged(change)
    local projectFileName = config.config.workspace.rojoProjectFile
    -- if change.uri:match("%.datamodel%.json$") then
    --     local path = uric.decode(change.uri)
    --     local filename = path:filename():string()
    --     if filename == projectFileName .. ".datamodel.json" then
    --         return true, true
    --     end
    if change.uri:match(projectFileName .. "%.project%.json$") then
        return true, true
    elseif change.type == 2 then
        local path = uric.decode(change.uri)
        local filename = path:filename():string()
        if fs.is_directory(path) or filename == "init.meta.json" or filename:match("%.model%.json$") then
            local relative = fs.relative(path):string()
            for _, src in pairs(self.Watch) do
                if relative:match("^"..src) then
                    return true
                end
            end
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

function rojo:loadRojoProject()
    self.RojoProject = {}
    self.Watch = {}
    if config.config.workspace.rojoProjectFile ~= "" then
        local filename = config.config.workspace.rojoProjectFile .. ".project.json"
        if fs.exists(fs.current_path() / filename) then
            local success, project = pcall(json.decode, readFile((fs.current_path() / filename):string()))
            if success and project.tree then
                self.RojoProject = {project}
            else
                return
            end
        end
    else
        for path in fs.current_path():list_directory() do
            if path:string():match("%.project%.json") then
                local success, project = pcall(json.decode, readFile(path:string()))
                if success and project.tree then
                    self.RojoProject[#self.RojoProject+1] = project
                end
            end
        end
    end
    if #self.RojoProject == 0 then
        return
    end
    local mainTree = {children = {}}
    for _, project in pairs(self.RojoProject) do
        local tree = {children = {}}
        getChildren(project.tree, tree)
        mainTree = table.merge(mainTree, tree)
    end
    table.sort(self.Watch, function(a, b) return #a > #b end)
    return mainTree
end

function rojo:searchRojoPaths(paths, tree, parent)
    for name, items in pairs(tree) do
        if not keys[name] then
            if items["$path"] then
                paths[#paths + 1] = {
                    path = parent .. "/" .. name,
                    uri = items["$path"]
                }
            end
            self:searchRojoPaths(paths, items, parent .. "/" .. name)
        end
    end
    return paths
end

return rojo