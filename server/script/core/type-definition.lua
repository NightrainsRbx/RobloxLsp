local guide      = require 'core.guide'
local files      = require 'files'
local vm         = require 'vm'
local findSource = require 'core.find-source'

local function sortResults(results)
    -- 先按照顺序排序
    table.sort(results, function (a, b)
        local u1 = guide.getUri(a.target)
        local u2 = guide.getUri(b.target)
        if u1 == u2 then
            return a.target.start < b.target.start
        else
            return u1 < u2
        end
    end)
    -- 如果2个结果处于嵌套状态，则取范围小的那个
    local lf, lu
    for i = #results, 1, -1 do
        local res  = results[i].target
        local f    = res.finish
        local uri = guide.getUri(res)
        if lf and f > lf and uri == lu then
            table.remove(results, i)
        else
            lu = uri
            lf = f
        end
    end
end

local accept = {
    ['local']       = true,
    ['setlocal']    = true,
    ['getlocal']    = true,
    ['field']       = true,
    ['method']      = true,
    ['setglobal']   = true,
    ['getglobal']   = true,
    ['...']         = true,
    ['type.name']   = true,
}

local function convertIndex(source)
    if not source then
        return
    end
    if source.type == 'string'
    or source.type == 'boolean'
    or source.type == 'number' then
        local parent = source.parent
        if not parent then
            return
        end
        if parent.type == 'setindex'
        or parent.type == 'getindex'
        or parent.type == 'tableindex' then
            return parent
        end
    end
    return source
end

return function (uri, offset)
    local ast = files.getAst(uri)
    if not ast then
        return nil
    end

    local source = convertIndex(findSource(ast, offset, accept))
    if not source then
        return nil
    end
    local results = {}
    local defs = {}
    local values = {}
    if source.type == "type.name" then
        defs[#defs+1] = source.typeAliasGeneric or vm.getTypeAlias(source)
    else
        for _, def in ipairs(vm.getDefs(source, 0, {skipDoc = true})) do
            if guide.isTypeAnn(def) then
                defs[#defs+1] = def
                if def.type == "type.name" or def.type == "type.module" then
                    defs[#defs+1] = def.typeAliasGeneric or vm.getTypeAlias(def)
                end
            end
        end
    end
    for _, src in ipairs(defs) do
        local value = guide.getObjectValue(src)
        if value and value ~= src then
            values[value] = true
        end
    end
    for _, src in ipairs(defs) do
        if src.dummy then
            goto CONTINUE
        end
        if values[src] then
            goto CONTINUE
        end
        local root = guide.getRoot(src)
        if not root then
            goto CONTINUE
        end
        if src.type == "type.field" then
            src = src.key
        end
        results[#results+1] = {
            target = src,
            uri    = files.getOriginUri(root.uri),
            source = source,
        }
        ::CONTINUE::
    end

    if #results == 0 then
        return nil
    end

    sortResults(results)

    return results
end
