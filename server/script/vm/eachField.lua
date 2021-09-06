---@type vm
local vm      = require 'vm.vm'
local guide   = require 'core.guide'
local await   = require 'await'
local config  = require 'config'

local function getFields(source, deep, filterKey, options)
    local unlock = vm.lock('eachField', source)
    if not unlock then
        return {}
    end

    while source.type == 'paren' do
        source = source.exp
        if not source then
            return {}
        end
    end
    deep = config.config.intelliSense.searchDepth + (deep or 0)

    await.delay()
    local results = guide.requestFields(source, vm.interface, deep, filterKey, options)
    
    unlock()
    return results
end

local function getFieldsBySource(source, deep, filterKey, options)
    deep = deep or -999
    local cache = vm.getCache('eachField', options)[source]
    if not cache or cache.deep < deep then
        cache = getFields(source, deep, filterKey, options)
        cache.deep = deep
        if not filterKey then
            vm.getCache('eachField', options)[source] = cache
        end
    end
    return cache
end

function vm.getFields(source, deep, options)
    if source.special == '_G' then
        if options and options.onlyDef then
            return vm.getGlobalSets('*', guide.getUri(source))
        else
            return vm.getGlobals('*', guide.getUri(source))
        end
    end
    if guide.isGlobal(source) then
        local name = guide.getKeyName(source)
        if not name then
            return {}
        end
        local cache =  vm.getCache('eachFieldOfGlobal', options)[name]
                    or getFieldsBySource(source, deep)
        vm.getCache('eachFieldOfGlobal', options)[name] = cache
        return cache
    else
        return getFieldsBySource(source, deep, nil, options)
    end
end
