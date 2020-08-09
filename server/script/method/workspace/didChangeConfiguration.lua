local rpc = require 'rpc'

--- @param lsp LSP
return function (lsp)
    for _, ws in ipairs(lsp.workspaces) do
        local uri = ws.uri
        -- 请求配置
        rpc:request('workspace/configuration', {
            items = {
                {
                    scopeUri = uri,
                    section = 'Lua',
                },
                {
                    scopeUri = uri,
                    section = 'files.associations',
                },
                {
                    scopeUri = uri,
                    section = 'files.exclude',
                }
            },
        }, function (configs)
            lsp:onUpdateConfig(configs[1], {
                associations = configs[2],
                exclude      = configs[3],
            })
        end)
    end
end
