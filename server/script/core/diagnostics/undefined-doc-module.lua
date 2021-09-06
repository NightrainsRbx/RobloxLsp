local files   = require 'files'
local ws      = require 'workspace'
local lang    = require 'language'

return function (uri, callback)
    local state = files.getAst(uri)
    if not state then
        return
    end

    if not state.ast.docs then
        return
    end

    for _, doc in ipairs(state.ast.docs) do
        if doc.type == 'doc.module' then
            if not doc.path then
                goto CONTINUE
            end
            local uris = ws.findUrisByRequirePath(doc.path)
            if #uris == 0 then
                callback {
                    start   = doc.start,
                    finish  = doc.finish,
                    message = lang.script('DIAG_UNDEFINED_MODULE')
                }
            end
        end
        ::CONTINUE::
    end
end
