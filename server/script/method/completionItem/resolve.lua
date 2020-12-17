local config = require 'config'
local listMgr = require 'vm.list'
local lang = require 'language'
local getFunctionHover = require 'core.hover.function'
local getFunctionHoverAsLib = require 'core.hover.lib_function'
local getFunctionHoverAsEmmy = require 'core.hover.emmy_function'

local function strip(str)
    local left = str:match("^[ ]*") or ""
    local right = str:match("[ ]*$") or ""
    return str:sub(1 + #left, #str - #right)
end

local function getDocumentation(name, value)
    if value:getType() == 'function' then
        local lib = value:getLib()
        local hover
        if lib then
            hover = getFunctionHoverAsLib(name, lib)
        else
            local emmy = value:getEmmy()
            if emmy and emmy.type == 'emmy.functionType' then
                hover = getFunctionHoverAsEmmy(name, emmy)
            else
                hover = getFunctionHover(name, value:getFunction())
            end
        end
        if not hover then
            return nil
        end
        local text = ([[
```lua
%s
```
%s
```lua
%s
```
%s
]]):format(hover.label or '', hover.description or '', hover.enum or '', hover.doc or '')
        return {
            kind = 'markdown',
            value = text,
        }
    end
    local lib = value:getLib()
    if lib then
        return {
            kind = 'markdown',
            value = lib.description,
        }
    end
    local comment = value:getComment()
    if comment then
        return {
            kind = 'markdown',
            value = comment,
        }
    end
    return nil
end

local function getDetail(value)
    local literal = value:getLiteral()
    local tp = type(literal)
    local detals = {}
    if value:getType() ~= 'any' then
        detals[#detals+1] = ('(%s)'):format(value:getType())
    end
    if tp == 'boolean' then
        detals[#detals+1] = (' = %q'):format(literal)
    elseif tp == 'string' then
        detals[#detals+1] =  (' = %q'):format(literal)
    elseif tp == 'number' then
        if math.type(literal) == 'integer' then
            detals[#detals+1] =  (' = %q'):format(literal)
        else
            local str = (' = %.16f'):format(literal)
            local dot = str:find('.', 1, true) or 0
            local suffix = str:find('[0]+$', dot + 2)
            if suffix then
                detals[#detals+1] =  str:sub(1, suffix - 1)
            else
                detals[#detals+1] =  str
            end
        end
    end
    if value:getType() == 'function' then
        ---@type emmyFunction
        local func = value:getFunction()
        local overLoads = func and func:getEmmyOverLoads()
        if overLoads then
            detals[#detals+1] = lang.script('HOVER_MULTI_PROTOTYPE', #overLoads + 1)
        end
    end
    if #detals == 0 then
        return nil
    end
    return table.concat(detals)
end

local documentationCache = {}
local cacheItems = 0

return function (lsp, item)
    if not item.data then
        return item
    end
    local id = item.data.id
    if documentationCache[id] then
        item.documentation = documentationCache[id].documentation
        item.detail = documentationCache[id].detail
    else
        local value = listMgr.valueList[id]
        if value then
            item.documentation = getDocumentation(item.data.name, value)
            item.detail = getDetail(value)
            if cacheItems > 500 then
                documentationCache = {}
                cacheItems = 0
            end
            cacheItems = cacheItems + 1
            documentationCache[id] = {
                documentation = item.documentation,
                detail = item.detail
            }
        end
    end
    local context = config.config.completion.displayContext
    if context <= 0 then
        return item
    end
    if not (item.data.offset and item.data.uri) then
        return item
    end
    local offset = item.data.offset
    local uri   = item.data.uri
    local _, lines, text = lsp:getVM(uri)
    if not lines then
        return item
    end
    local row = lines:rowcol(offset)
    local firstRow = lines[row]
    local lastRow = lines[math.min(row + context - 1, #lines)]
    local snip = strip(text:sub(firstRow.start, lastRow.finish))
    local document = ([[
%s

------------
```lua
%s
```
]]):format(item.documentation and item.documentation.value or '', snip)
    item.documentation = {
        kind  = 'markdown',
        value = document,
    }
    return item
end
