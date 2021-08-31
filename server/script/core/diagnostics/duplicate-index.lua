local files   = require 'files'
local guide   = require 'core.guide'
local lang    = require 'language'
local define  = require 'proto.define'
local vm      = require 'vm'

return function (uri, callback)
    local ast = files.getAst(uri)
    if not ast then
        return
    end

    guide.eachSourceType(ast.ast, 'table', function (source)
        local mark = {}
        for _, obj in ipairs(source) do
            if obj.type == 'tablefield'
            or obj.type == 'tableindex' then
                local name = vm.getKeyName(obj)
                local tp = vm.getKeyType(obj)
                if name then
                    if not mark[tp] then
                        mark[tp] = {}
                    end
                    if not mark[tp][name] then
                        mark[tp][name] = {}
                    end
                    mark[tp][name][#mark[tp][name]+1] = obj.field or obj.index
                end
            end
        end
        for tp, mark in pairs(mark) do
            for name, defs in pairs(mark) do
                if #defs > 1 and name then
                    local related = {}
                    for i = 1, #defs do
                        local def = defs[i]
                        related[i] = {
                            start  = def.start,
                            finish = def.finish,
                            uri    = uri,
                        }
                    end
                    for i = 1, #defs - 1 do
                        local def = defs[i]
                        callback {
                            start   = def.start,
                            finish  = def.finish,
                            related = related,
                            message = lang.script('DIAG_DUPLICATE_INDEX', name),
                            level   = define.DiagnosticSeverity.Hint,
                            tags    = { define.DiagnosticTag.Unnecessary },
                        }
                    end
                    for i = #defs, #defs do
                        local def = defs[i]
                        callback {
                            start   = def.start,
                            finish  = def.finish,
                            related = related,
                            message = lang.script('DIAG_DUPLICATE_INDEX', name),
                        }
                    end
                end
            end
        end

    end)
end
