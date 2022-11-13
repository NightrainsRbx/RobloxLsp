local sp         = require 'bee.subprocess'
local nonil      = require 'without-check-nil'
local client     = require 'provider.client'
local platform   = require 'bee.platform'
local completion = require 'provider.completion'

local m = {}

local function testFileEvents(initer)
    initer.fileOperations = {
        didCreate = {
            filters = {
                {
                    pattern = {
                        glob = '**',
                        --matches = 'file',
                        options = platform.OS == 'Windows',
                    }
                }
            }
        },
        didDelete = {
            filters = {
                {
                    pattern = {
                        glob = '**',
                        --matches = 'file',
                        options = platform.OS == 'Windows',
                    }
                }
            }
        },
        didRename = {
            filters = {
                {
                    pattern = {
                        glob = '**',
                        --matches = 'file',
                        options = platform.OS == 'Windows',
                    }
                }
            }
        },
    }
end

function m.getIniter()
    local initer = {
        -- 文本同步方式
        textDocumentSync = {
            -- 打开关闭文本时通知
            openClose = true,
            -- 文本增量更新
            change = 2,
        },

        hoverProvider = true,
        definitionProvider = true,
        typeDefinitionProvider = true,
        referencesProvider = true,
        renameProvider = {
            prepareProvider = true,
        },
        documentSymbolProvider = true,
        workspaceSymbolProvider = true,
        documentHighlightProvider = true,
        colorProvider = true,
        documentLinkProvider = true,
        codeActionProvider = {
            codeActionKinds = {
                '',
                'quickfix',
                'refactor.rewrite',
                'refactor.extract',
            },
            resolveProvider = true,
        },
        signatureHelpProvider = {
            triggerCharacters = { '(', ',' },
        },
        executeCommandProvider = {
            commands = {
                'lua.removeSpace:' .. sp:get_id(),
                'lua.solve:'       .. sp:get_id(),
                'lua.jsonToLua:'   .. sp:get_id(),
            },
        },
        foldingRangeProvider = true,
        documentOnTypeFormattingProvider = {
            firstTriggerCharacter = '\n',
            moreTriggerCharacter  = nil, -- string[]
         },
        --documentOnTypeFormattingProvider = {
        --    firstTriggerCharacter = '}',
        --},
    }

    --testFileEvents()

    nonil.enable()
    if not client.info.capabilities.textDocument.completion.dynamicRegistration then
        initer.completionProvider = {
            resolveProvider = true,
            triggerCharacters = completion.allWords(),
            completionItem = {
                labelDetailsSupport = true
            }
        }
    end
    nonil.disable()

    return initer
end

return m
