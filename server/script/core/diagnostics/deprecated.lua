local files   = require 'files'
local vm      = require 'vm'
local lang    = require 'language'
local guide   = require 'core.guide'
local config  = require 'config'
local define  = require 'proto.define'
local await   = require 'await'

return function (uri, callback)
    local ast = files.getAst(uri)
    if not ast then
        return
    end

    guide.eachSource(ast.ast, function (src)
        if  src.type ~= 'getglobal'
        and src.type ~= 'getfield'
        and src.type ~= 'getindex'
        and src.type ~= 'getmethod' then
            return
        end
        if src.type == 'getglobal' then
            local key = guide.getKeyName(src)
            if not key then
                return
            end
            if config.config.diagnostics.globals[key] then
                return
            end
        else
            if not src.field and not src.method and not src.index then
                return
            end
            if src.index and src.index.type ~= "string" then
                return
            end
        end

        await.delay()

        if not vm.isDeprecated(src, 0) then
            return
        end
        src = src.field or src.method or src.index or src
        callback {
            start   = src.start,
            finish  = src.finish,
            tags    = { define.DiagnosticTag.Deprecated },
            message = lang.script("DIAG_DEPRECATED", guide.getKeyName(src))
        }
    end)
end
