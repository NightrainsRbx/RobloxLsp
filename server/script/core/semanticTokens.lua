local TokenTypes     = require 'constant.TokenTypes'
local TokenModifiers = require 'constant.TokenModifiers'
local findLib        = require 'core.find_lib'
local rbxapi         = require 'rbxapi'

local constLib = {
    ['math.pi']           = true,
    ['math.huge']         = true,
    ['math.maxinteger']   = true,
    ['math.mininteger']   = true,
    ['utf8.charpattern']  = true,
    ['io.stdin']          = true,
    ['io.stdout']         = true,
    ['io.stderr']         = true,
    ['package.config']    = true,
    ['package.cpath']     = true,
    ['package.loaded']    = true,
    ['package.loaders']   = true,
    ['package.path']      = true,
    ['package.preload']   = true,
    ['package.searchers'] = true,
}

local ignore = {
    ['_G']                = true,
    ['_VERSION']          = true,
    ['workspace']         = true,
    ['game']              = true,
    ['script']            = true,
    ['plugin']            = true,
    ['shared']            = true,
}

local luauTypeSources = {
    ["varType"]           = true,
    ["paramType"]         = true,
    ["returnType"]        = true,
    ["typeDef"]           = true,
    ["typeGenerics"]      = true,
}

local function findNameTypes(info, ret)
    ret = ret or {}
    for _, v in pairs(info) do
        if type(v) == "table" then
            findNameTypes(v, ret)
        elseif v == "nameType" then
            ret[#ret+1] = info
        end
    end
    return ret
end

return {
    luauTypeSources = luauTypeSources,
    findNameTypes = findNameTypes,
    Care = {
        ['name'] = function(source, sources)
            if source[1] == '' then
                return
            end
            if ignore[source[1]] then
                return
            end
            if source:get 'global' then
                if rbxapi.Constructors[source[1]] then
                    sources[#sources+1] = {
                        start      = source.start,
                        finish     = source.finish,
                        type       = TokenTypes.class,
                        modifieres = TokenModifiers.static,
                    }
                    return
                end
                local lib = findLib(source)
                if lib then
                    if lib.type == "Enums" then
                        return
                    end
                    sources[#sources+1] = {
                        start      = source.start,
                        finish     = source.finish,
                        type       = TokenTypes.namespace,
                        modifieres = TokenModifiers.static,
                    }
                    return
                end
                sources[#sources+1] = {
                    start      = source.start,
                    finish     = source.finish,
                    type       = TokenTypes.namespace,
                    modifieres = TokenModifiers.deprecated,
                }
            elseif source:get 'table index' then
                if source._action == "set" then
                    sources[#sources+1] = {
                        start      = source.start,
                        finish     = source.finish,
                        type       = TokenTypes.property,
                        modifieres = TokenModifiers.declaration,
                    }
                end
            elseif source:bindLocal() then
                if source:get 'arg' then
                    sources[#sources+1] = {
                        start      = source.start,
                        finish     = source.finish,
                        type       = TokenTypes.parameter,
                        modifieres = TokenModifiers.declaration,
                    }
                elseif source:bindLocal():getSource():get 'arg' then
                    sources[#sources+1] = {
                        start      = source.start,
                        finish     = source.finish,
                        type       = TokenTypes.parameter,
                    }
                end
                if source[1] == '_ENV'
                or source[1] == 'self' then
                    return
                end
                local value = source:bindValue()
                local func = value:getFunction()
                if func and func:getSource().name == source then
                    sources[#sources+1] = {
                        start      = source.start,
                        finish     = source.finish,
                        type       = TokenTypes["function"],
                        modifieres = TokenModifiers.declaration,
                    }
                    return
                end
                
            elseif source:bindValue() then
                local lib = findLib(source)
                if lib and lib.doc and constLib[lib.doc] then
                    table.remove(sources, #sources)
                    return
                end
            end
        end,
        ['emmyType'] = function(source, sources)
            for type in pairs(luauTypeSources) do
                if source[type] then
                    for _, nameType in pairs(findNameTypes(source[type].info)) do
                        sources[#sources+1] = {
                            start      = nameType.start,
                            finish     = nameType.finish,
                            type       = TokenTypes.type,
                            modifieres = TokenModifiers.static,
                        }
                    end
                end
            end
        end,
        ['number'] = function(source, sources)
            sources[#sources+1] = {
                start      = source.start,
                finish     = source.finish,
                type       = TokenTypes.number,
                modifieres = TokenModifiers.static,
            }
        end
    }
}