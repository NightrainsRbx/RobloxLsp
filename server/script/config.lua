<<<<<<< HEAD
local DiagnosticDefaultSeverity = require 'constant.DiagnosticDefaultSeverity'
local rpc = require 'rpc'
=======
local util   = require 'utility'
local define = require 'proto.define'

local m = {}
m.version = 0
>>>>>>> origin/master

local function Boolean(v)
    if type(v) == 'boolean' then
        return true, v
    end
    return false
end

local function Integer(v)
    if type(v) == 'number' then
        return true, math.floor(v)
    end
    return false
end

local function String(v)
    return true, tostring(v)
end

<<<<<<< HEAD
=======
local function Nil(v)
    if type(v) == 'nil' then
        return true, nil
    end
    return false
end

>>>>>>> origin/master
local function Str2Hash(sep)
    return function (v)
        if type(v) == 'string' then
            local t = {}
            for s in v:gmatch('[^'..sep..']+') do
                t[s] = true
            end
            return true, t
        end
        if type(v) == 'table' then
            local t = {}
            for _, s in ipairs(v) do
                if type(s) == 'string' then
                    t[s] = true
                end
            end
            return true, t
        end
        return false
    end
end

<<<<<<< HEAD
=======
local function Array2Hash(checker)
    return function (tbl)
        if type(tbl) ~= 'table' then
            return false
        end
        local t = {}
        if #tbl > 0 then
            for _, k in ipairs(tbl) do
                t[k] = true
            end
        else
            for k, v in pairs(tbl) do
                t[k] = v
            end
        end
        return true, t
    end
end

>>>>>>> origin/master
local function Array(checker)
    return function (tbl)
        if type(tbl) ~= 'table' then
            return false
        end
        local t = {}
        for _, v in ipairs(tbl) do
            local ok, result = checker(v)
            if ok then
                t[#t+1] = result
            end
        end
        return true, t
    end
end

local function Hash(keyChecker, valueChecker)
    return function (tbl)
        if type(tbl) ~= 'table' then
            return false
        end
        local t = {}
        for k, v in pairs(tbl) do
            local ok1, key = keyChecker(k)
            local ok2, value = valueChecker(v)
            if ok1 and ok2 then
                t[key] = value
            end
        end
        if not next(t) then
            return false
        end
        return true, t
    end
end

local function Or(...)
    local checkers = {...}
    return function (obj)
        for _, checker in ipairs(checkers) do
            local suc, res = checker(obj)
            if suc then
                return true, res
            end
        end
        return false
    end
end

<<<<<<< HEAD
-- Just a copy and paste from the utility script.
-- This is a fix for the early log.debug stuff at the start
function table.deepCopy(a)
    local t = {}
    for k, v in pairs(a) do
        if type(v) == 'table' then
            t[k] = table.deepCopy(v)
        else
            t[k] = v
        end
    end
    return t
end


local ConfigTemplate = {
    runtime = {
        version         = {'Luau', String},
        library         = {{},        Str2Hash ';'},
        path            = {{
=======
local ConfigTemplate = {
    runtime = {
        path              = {{
>>>>>>> origin/master
                                "?.lua",
                                "?/init.lua",
                                "?/?.lua"
                            },        Array(String)},
<<<<<<< HEAD
    },
    diagnostics = {
        enable            = {true, Boolean},
        syntax            = {true, Boolean},
        datamodelAsIgnore = {true, Boolean},
        globals           = {{},   Str2Hash ';'},
        ignore            = {{},   Str2Hash ';'},
        disable           = {{},   Str2Hash ';'},
        severity          = {
            table.deepCopy(DiagnosticDefaultSeverity),
            Hash(String, String),
        },
=======
        meta              = {'${version} ${language}', String},
        plugin            = {'.vscode/lua/plugin.lua', String},
        fileEncoding      = {'utf8',    String},
    },
    diagnostics = {
        enable          = {true, Boolean},
        globals         = {{},   Str2Hash ';'},
        disable         = {{},   Str2Hash ';'},
        severity        = {
            util.deepCopy(define.DiagnosticDefaultSeverity),
            Hash(String, String),
        },
        neededFileStatus = {
            util.deepCopy(define.DiagnosticDefaultNeededFileStatus),
            Hash(String, String),
        },
        workspaceDelay  = {0,    Integer},
        workspaceRate   = {100,  Integer},
>>>>>>> origin/master
    },
    workspace = {
        ignoreDir       = {{},      Str2Hash ';'},
        ignoreSubmodules= {true,    Boolean},
        rojoProjectFile = {"default",    String},
        loadMode        = {'All Files', String},
        useGitIgnore    = {true,    Boolean},
<<<<<<< HEAD
        maxPreload      = {300,     Integer},
        preloadFileSize = {100,     Integer},
        library         = {{},      Hash(
                                        String,
                                        Or(Boolean, Array(String))
                                    )}
    },
    completion = {
        enable             = {true,      Boolean},
        serverPort         = {27843,     Integer},
        fastAutocompletion = {true,      Boolean},
        endAutocompletion  = {true,      Boolean},
        callSnippet        = {'Disable', String},
        keywordSnippet     = {'Replace', String},
        displayContext     = {6,         Integer},
    },
    signatureHelp = {
        enable          = {true,      Boolean},
=======
        maxPreload      = {1000,    Integer},
        preloadFileSize = {100,     Integer},
        library         = {{},      Array2Hash(String)},
    },
    completion = {
        enable             = {true,      Boolean},
        callParenthesess   = {false,     Boolean},
        keywordSnippet     = {'Replace', String},
        displayContext     = {0,         Integer},
        endAutocompletion  = {false,     Boolean},
        workspaceWord      = {true,      Boolean},
        showParams         = {true,      Boolean},
        deprecatedMembers  = {false,     Boolean},
    },
    signatureHelp = {
        enable          = {true,      Boolean},
        documentation   = {true,      Boolean},
>>>>>>> origin/master
    },
    hover = {
        enable          = {true,      Boolean},
        viewString      = {true,      Boolean},
        viewStringMax   = {1000,      Integer},
        viewNumber      = {true,      Boolean},
<<<<<<< HEAD
=======
        fieldInfer      = {3000,      Integer},
        previewFields   = {100,       Integer},
        enumsLimit      = {5,         Integer},
>>>>>>> origin/master
    },
    color = {
        mode            = {'Semantic', String},
    },
<<<<<<< HEAD
    misc = {
        color3Picker    = {true,      Boolean},
        goToScriptLink  = {true,      Boolean},
    },
    plugin = {
        enable          = {false, Boolean},
        path            = {'.vscode/lua-plugin/*.lua', String},
    },
    logging = {
        showDebugMessages = {false, Boolean}
=======
    hint = {
        enable          = {false,     Boolean},
        variableType    = {true,      Boolean},
        paramType       = {true,      Boolean},
        setType         = {false,     Boolean},
        returnType      = {false,     Boolean},
        paramName       = {false,     Boolean},
    },
    intelliSense = {
        searchDepth     = {0,         Integer},
    },
    window              = {
        statusBar       = {true,      Boolean},
        progressBar     = {true,      Boolean},
    },
    misc = {
        color3Picker      = {true,      Boolean},
        goToScriptLink    = {true,      Boolean},
        serviceAutoImport = {true,      Boolean},
        serverPort        = {27843,       Integer},
    },
    typeChecking = {
        mode            = {'Disabled', String},
        options         = {
            util.shallowCopy(define.TypeCheckingOptions),
            Hash(String, Boolean),
        },
        showFullType    = {false,       Boolean},
>>>>>>> origin/master
    }
}

local OtherTemplate = {
<<<<<<< HEAD
    associations = {{}, Hash(String, String)},
    exclude =      {{}, Hash(String, Boolean)},
}

local Config, Other

local function init()
    if Config then
        return
    end

    Config = {}
    for c, t in pairs(ConfigTemplate) do
        Config[c] = {}
        for k, info in pairs(t) do
            Config[c][k] = info[1]
        end
    end

    Other = {}
    for k, info in pairs(OtherTemplate) do
        Other[k] = info[1]
    end
end

local function setConfig(self, config, other)
=======
    associations            = {{},   Hash(String, String)},
    exclude                 = {{},   Hash(String, Boolean)},
    semantic                = {'',   Or(Boolean, String)},
    acceptSuggestionOnEnter = {'on', String},
}

local function init()
    if m.config then
        return
    end

    m.config = {}
    for c, t in pairs(ConfigTemplate) do
        m.config[c] = {}
        for k, info in pairs(t) do
            m.config[c][k] = info[1]
        end
    end

    m.other = {}
    for k, info in pairs(OtherTemplate) do
        m.other[k] = info[1]
    end
end

function m.setConfig(config, other)
    m.version = m.version + 1
>>>>>>> origin/master
    xpcall(function ()
        for c, t in pairs(config) do
            for k, v in pairs(t) do
                local region = ConfigTemplate[c]
                if region then
                    local info = region[k]
                    if info then
                        local suc, v = info[2](v)
                        if suc then
<<<<<<< HEAD
                            Config[c][k] = v
                        else
                            Config[c][k] = info[1]
=======
                            m.config[c][k] = v
                        else
                            m.config[c][k] = info[1]
>>>>>>> origin/master
                        end
                    end
                end
            end
        end
        for k, v in pairs(other) do
            local info = OtherTemplate[k]
            if info then
                local suc, v = info[2](v)
                if suc then
<<<<<<< HEAD
                    Other[k] = v
                else
                    Other[k] = info[1]
                end
            end
        end
        log.debug('Config update: ', table.dump(Config), table.dump(Other))
    end, function(err)
        rpc:notify('window/showMessage', {
            type = 1,
            message = "Error Loading Config: " .. err,
        })
    end)
=======
                    m.other[k] = v
                else
                    m.other[k] = info[1]
                end
            end
        end
        log.debug('Config update: ', util.dump(m.config), util.dump(m.other))
    end, log.error)
>>>>>>> origin/master
end

init()

<<<<<<< HEAD
return {
    setConfig = setConfig,
    config = Config,
    isLuau = function()
        return Config.runtime.version == "Luau"
    end,
    other = Other,
}
=======
return m
>>>>>>> origin/master
