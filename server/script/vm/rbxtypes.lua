local rbxApi = require 'rbxapi'
local rojo = require 'rojo'
local config = require 'config'
local createMulti = require 'vm.multi'
local libraryBuilder = require 'vm.library'
local library = require 'core.library'
local valueMgr = require 'vm.value'
local fs = require 'bee.filesystem'
local mt = require 'vm.manager'
local uri = require 'uri'

function mt:getArgString(source)
    if source.type == "string" then
        return source[1]
    elseif source.type == "name" then
        source = self:getName(source:getName(), source)
        if source and source:getType() == "string" then
            return source:getLiteral()
        end
    elseif source.type == "simple" then
        source = self:getSimple(source)
        if source and source.type == "multi" then
            source = self:getFirstInMulti(source)
        end
        if source and source:getType() == "string" then
            return source:getLiteral()
        end
    end
end

function mt:getArgFunction(source)
    if source.type == "function" then
        source = source:bindFunction():getFunction()
        if source and source.args and #source.args > 0 then
            return source
        end
    elseif source.type == "name" then
        source = self:getName(source:getName(), source)
        if source and source:getType() == "function" then
            source = source:getFunction()
            if source and source.args and #source.args > 0 then
                return source
            end
        end
    elseif source.type == "simple" then
        source = self:getSimple(source)
        if source and source.type == "multi" then
            source = self:getFirstInMulti(source)
        end
        if source and source:getType() == "function" then
            source = source:getFunction()
            if source and source.args and #source.args > 0 then
                return source
            end
        end
    end
end

function mt:getArgInstance(source)
    if source.type == "name" then
        source = source:bindValue()
        if source and rbxApi:isInstance(source:getType()) then
            return source
        end
    elseif source.type == "simple" then
        source = self:getSimple(source)
        if source and source.type == "multi" then
            source = self:getFirstInMulti(source)
        end
        if source and rbxApi:isInstance(source:getType()) then
            return source
        end
    end
end

function mt:fixParamType(type)
    if type then
        type = type:gsub("^[%w_]+%: ", "")
        if type:sub(1, 5) == "Enum." then
            return "EnumItem"
        elseif type == "Tuple" then
            return "any"
        end
    end
    return type
end

local primitiveTypes = {
    ['any'] = true,
    ['string'] = true,
    ['number'] = true,
    ['integer'] = true,
    ['boolean'] = true,
    ['table'] = true,
    ['function'] = true,
    ['nil'] = true,
    ['userdata'] = true,
    ['thread'] = true,
    ['Objects'] = true,
    ['Array'] = true,
    ['Map'] = true,
    ['Dictionary'] = true,
    ['Tuple'] = true
}

function mt:createLibValue(type, source)
    local value = self:createValue(type, source)
    if primitiveTypes[type] or not library.object[type] then
        return value
    end
    value:setLib(libraryBuilder.value(library.object[type]):getLib())
    return value
end

function mt:getCall(simple, source)
    self:instantSource(simple)
    local func = nil
    for _, item in ipairs(simple) do
        if item.type == "name" and item.finish == source.start - 1 then
            func = item
            break
        end
    end
    if not func then
        return
    end
    self:instantSource(func)
    local value = self:getFirstInMulti(self:getExp(func))
    if not value then
        return
    end
    local values = self:unpackList(source)
    source:bindCall(source._bindCallArgs)
    return self:call(value, values, source, true)
end

function mt:doTypedFunction(source)
    if not config.isLuau() then
        return
    end
    local args = source._bindCallArgs
    if not (args and #args > 0) then
        return
    end
    local simple = source:get 'simple'
    if not simple then
        return
    end
    local funcName = nil
    for _, item in ipairs(simple) do
        if item.type == "name" and item.finish == source.start - 1 then
            funcName = item
            break
        end
    end
    if not funcName then
        return
    end
    if source:get 'has object' then
        local object = args[1]
        if object.type == "call" then
            object = self:getCall(simple, object)
            if object then
                object = self:getFirstInMulti(object)
            end
        else
            object = object:bindValue()
        end
        if not object then
            return
        end
        if #args > 1 and rbxApi.TypedFunctions[funcName[1]] then
            if not rbxApi:isInstance(object:getType()) then
                return
            end
            local className = self:getArgString(args[2])
            if not className then
                return
            end
            if funcName[1] == "GetService" then
                if not (rbxApi:isA(object:getType(), "ServiceProvider") and rbxApi.Services[className]) then
                    return
                end
            elseif not rbxApi.ClassNames[className] then
                return
            end
            local returns = createMulti()
            local value = self:createLibValue(className, source)
            returns:push(value)
            return returns
        elseif #args > 1 and (funcName[1] == "FindFirstChild" or funcName[1] == "WaitForChild") then
            if not rbxApi:isInstance(object:getType()) then
                return
            end
            local childName = self:getArgString(args[2])
            if not childName then
                return
            end
            local child = object:getChild(childName, source, source.uri)
            if child and child:getLib() and child:getLib().obj then
                local returns = createMulti()
                returns:push(child)
                return returns
            end
        elseif object:getType() == "RBXScriptSignal" then
            local lib = object:getLib()
            if not lib then
                return
            end
            if not (rbxApi.EventsParameters[lib.name] and rbxApi.EventsParameters[lib.name][lib.parentClass]) then
                return
            end
            if funcName[1] == "Wait" or funcName[1] == "wait" then
                local returns = createMulti()
                for _, param in pairs(rbxApi.EventsParameters[lib.name][lib.parentClass]) do
                    local value = self:createLibValue(self:fixParamType(param), source)
                    returns:push(value)
                end
                return returns
            elseif (funcName[1] == "Connect" or funcName[1] == "connect") and args[2] then
                local callback = self:getArgFunction(args[2])
                if not callback then
                    return
                end
                local types = rbxApi.EventsParameters[lib.name][lib.parentClass]
                local values = createMulti()
                for i = 1, #callback.args, 1 do
                    if types[i] then
                        local value = self:createLibValue(self:fixParamType(types[i]), source)
                        values:push(value)
                    end
                end
                callback:setArgs(values)
                self:runFunction(callback)
            end
        end
    elseif funcName[1] == "new" then
        local parent = funcName:get 'parent'
        if not parent then
            return
        end
        local lib = parent:getLib()
        if not (lib and lib.name == "Instance") then
            return
        end
        local className = self:getArgString(args[1])
        if not (className and rbxApi.CreatableInstances[className]) then
            return
        end
        local value = self:createLibValue(className, source)
        if args[2] then
            local parentInstance = self:getArgInstance(args[2])
            if not parentInstance then
                return
            end
            value:setChild("Parent", parentInstance, source, source.uri)
        end
        local returns = createMulti()
        returns:push(value)
        return returns
    end
end

local function fixType(tp)
    if tp == "integer" or tp == "float" or tp == "double" then
        return "number"
    end
    return tp
end

function mt:getRbxBinaryExp(v1, v2, op)
    local tp1 = fixType(v1:getType())
    local tp2 = fixType(v2:getType())
    if (op == "+"
    or op == "-")
    then
        if tp1 == "Vector3" and tp2 == "Vector3" then
            return "Vector3"
        end
        if tp1 == "Vector2" and tp2 == "Vector2" then
            return "Vector2"
        end
        if tp1 == "UDim" and tp2 == "UDim" then
            return "UDim"
        end
        if tp1 == "UDim2" and tp2 == "UDim2" then
            return "UDim2"
        end
        if tp1 == "CFrame" and tp2 == "Vector3" then
            return "CFrame"
        end
    end
    if (op == "*"
    or op == "/")
    then
        if (tp1 == "Vector3" and (tp2 == "Vector3" or tp2 == "number"))
        or (tp2 == "Vector3" and (tp1 == "Vector3" or tp1 == "number")) then
            return "Vector3"
        end
        if (tp1 == "Vector2" and (tp2 == "Vector2" or tp2 == "number"))
        or (tp2 == "Vector2" and (tp1 == "Vector2" or tp1 == "number")) then
            return "Vector2"
        end
        if (tp1 == "Vector3int16" and (tp2 == "Vector3in16" or tp2 == "number"))
        or (tp2 == "Vector3in16" and (tp1 == "Vector3in16" or tp1 == "number")) then
            return "Vector3in16"
        end
        if (tp1 == "Vector2int16" and (tp2 == "Vector2in16" or tp2 == "number"))
        or (tp2 == "Vector2in16" and (tp1 == "Vector2in16" or tp1 == "number")) then
            return "Vector2in16"
        end
    end
    if op == "*" then
        if tp1 == "CFrame" and tp2 == "Vector3" then
            return "Vector3"
        end
        if tp1 == "CFrame" and tp2 == "CFrame" then
            return "CFrame"
        end
    end
    if op ~= "*" and op ~= "+" and op ~= "-" and op ~= "/" then
        return
    end
    if tp1 == "Vector3int16" and tp2 == "Vector3in16" then
        return "Vector3in16"
    end
    if tp1 == "Vector2int16" and tp2 == "Vector2in16" then
        return "Vector2in16"
    end
    if rbxApi:getTypes()[tp1] or rbxApi:getTypes()[tp2] then
        return "nil"
    end
end

local rojoDescriptions = {
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

local function removeLuaExtension(str)
    return str:gsub("%.server%.lua", ""):gsub("%.client%.lua", ""):gsub("%.lua", "")
end

local function readFile(path)
    local file = io.open(tostring(path))
    local contents = file:read("*a")
    file:close()
    return contents
end

function mt:findScriptByPath(uri)
    if #rojo.RojoProject == 0 then
        return
    end
    local path = nil
    local rojoPaths = {}
    for _, project in pairs(rojo.RojoProject) do
        rojo:searchRojoPaths(rojoPaths, project.tree, "")
    end
    table.sort(rojoPaths, function(a, b) return #a.uri > #b.uri end)
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
    local ENV = self.envType == '_ENV' and self:loadLocal('_ENV') or self:loadLocal('@ENV')
    if not ENV then
        return
    end
    local current = ENV:getValue():getChild("game", nil, "@global")
    if not current:getType() == "DataModel" then
        return
    end
    for _, name in pairs(split(path,'[\\/]+')) do
        local child = current:getChild(name, nil, uri)
        if child and rbxApi:isInstance(child:getType()) then
            current = child
        end
    end
    if current then
        local script = current:getChild(fileName, nil, uri)
        if script and rbxApi:isA(script:getType(), "LuaSourceContainer") then
            return script
        end
    end
end

function mt:findPathByScript(script)
    if #rojo.RojoProject == 0 then
        return
    end
    if not (script._lib and script._lib.path) then
        return
    end
    local path = script._lib.path
    local rojoPaths = {}
    for _, project in pairs(rojo.RojoProject) do
        rojo:searchRojoPaths(rojoPaths, project.tree, "")
    end
    table.sort(rojoPaths, function(a, b) return #a.uri > #b.uri end)
    for _, info in pairs(rojoPaths) do
        local _, finish = path:find(info.path, 1, true)
        if finish then
            path = info.uri .. path:sub(finish + 1)
            break
        end
    end
    return path:gsub("%/", ".")
end

function mt:isRoact(value, path, requireValue)
    if value:getType() == "string" then
        if value._literal and value._literal:lower():match("roact") then
            return true
        end
        return
    end
    if path and not path:lower():match("roact") then
       return
    end
    if (not value._child) or value:getType() ~= "ModuleScript" then
        return
    end
    local children = {
        "None",
        "Binding",
        "Logging",
        "createContext",
        "Component",
        "createRef",
        "ComponentLifecyclePhase",
        "RobloxRenderer",
        "ElementUtils",
        "SingleEventManager",
        "PropMarkers",
        "getDefaultInstanceProperty",
        "Symbol",
        "ElementKind",
        "PureComponent",
        "Portal",
        "strict",
        "assertDeepEqual",
        "createSpy",
        "oneChild",
        "Config",
        "NoopRenderer",
        "internalAssert",
        "assign",
        "createReconciler",
        "createFragment",
        "createReconcilerCompat",
        "Type",
        "createElement",
        "invalidSetStateMessages",
        "createSignal",
        "GlobalConfig",
    }
    for child in pairs(value._child) do
        for index, childName in pairs(children) do
            if child == childName then
                table.remove(children, index)
                break
            end
        end
        if #children < 16 then
            break
        end
    end
    if #children < 16 then
        return true
    end
    if requireValue and requireValue.uri then
        local success, source = pcall(readFile, uri.decode(requireValue.uri))
        if success and source:match("Roact") and source:match("Rotriever") then
            return true
        end
    end
end

function mt:isRodux(value, path, requireValue)
    if value:getType() == "string" then
        if value._literal and value._literal:lower():match("rodux") then
            return true
        end
        return
    end
    if path and not path:lower():match("rodux") then
       return
    end
    if (not value._child) or value:getType() ~= "ModuleScript" then
        return
    end
    local children = {
        "combineReducers",
        "createReducer",
        "loggerMiddleware",
        "NoYield",
        "Signal",
        "Store",
        "thunkMiddleware"
    }
    for child in pairs(value._child) do
        for index, childName in pairs(children) do
            if child == childName then
                table.remove(children, index)
                break
            end
        end
        if #children == 0 then
            break
        end
    end
    if #children == 0 then
        return true
    end
    if requireValue and requireValue.uri then
        local success, source = pcall(readFile, uri.decode(requireValue.uri))
        if success and source:lower():match("rodux") and source:match("Rotriever") then
            return true
        end
    end
end

function mt:searchAeroModules(value)
    local currentPath = fs.current_path()
    if fs.exists(currentPath / "src") then
        currentPath = currentPath / "src"
    else
        return
    end
    local lib = value:getLib()
    local modulesPath = nil
    if lib.doc == "AeroService.Modules" then
        if fs.exists(currentPath / "Server" / "Modules") then
            modulesPath = currentPath / "Server" / "Modules"
        end
    elseif lib.doc == "AeroController.Modules" then
        if fs.exists(currentPath / "Client" / "Modules") then
            modulesPath = currentPath / "Client" / "Modules"
        end
    elseif lib.doc == "AeroService.Shared" or lib.doc == "AeroController.Shared" then
        if fs.exists(currentPath / "Shared") then
            modulesPath = currentPath / "Shared"
        end
    end
    if not modulesPath then
        return
    end
    local ws = self.lsp:findWorkspaceFor(self:getUri())
    if not ws then
        return
    end
    for path in modulesPath:list_directory() do
        path = tostring(path)
        local fileName = nil
        for str in path:gmatch(".+/(.+)$") do
            fileName = str
        end
        if not fileName then
            goto CONTINUE
        end
        path = path:gsub(tostring(fs.current_path()), ""):gsub("%/", "."):sub(2)
        path = removeLuaExtension(path)
        local moduleUri = ws:searchPath(self:getUri(), path)
        if moduleUri then
            self.lsp:compileChain(self:getUri(), moduleUri)
            local module = self.lsp.chain:get(moduleUri)
            if module then
                value:setChild(removeLuaExtension(fileName), module, self:getDefaultSource(), self:getUri())
            end
        end
        ::CONTINUE::
    end
end
