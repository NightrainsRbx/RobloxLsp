local files   = require 'files'
local ws      = require 'workspace'
local lang    = require 'language'
local config  = require 'config'
local fs      = require 'bee.filesystem'

return function (uri, callback)
    local state = files.getAst(uri)
    if not state or not state.ast.docs then
        return
    end
    for _, doc in ipairs(state.ast.docs) do
        if doc.type == 'doc.module' then
            if not doc.path then
                goto CONTINUE
            end
            local uris = ws.findUrisByRequirePath(doc.path)
            if #uris > 0 then
                goto CONTINUE
            end
            local input = doc.path:gsub('%.', '/'):gsub('%%', '%%%%')
            for _, luapath in ipairs(config.config.runtime.path) do
                local path = fs.path(ws.normalize(luapath:gsub('%?', input)))
                if fs.exists(path) then
                    goto CONTINUE
                end
            end
            callback {
                start   = doc.start,
                finish  = doc.finish,
                message = lang.script('DIAG_UNDEFINED_MODULE')
            }
        end
        ::CONTINUE::
    end
end
