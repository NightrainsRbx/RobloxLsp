local await    = require 'await'
local proto    = require 'proto.proto'
local define   = require 'proto.define'
local lang     = require 'language'
local files    = require 'files'
local config   = require 'config'
local core     = require 'core.diagnostics'
local util     = require 'utility'
local ws       = require 'workspace'
local progress = require "progress"

local m = {}
m._start = false
m.cache = {}
m.sleepRest = 0.0

local function concat(t, sep)
    if type(t) ~= 'table' then
        return t
    end
    return table.concat(t, sep)
end

local function buildSyntaxError(uri, err)
    local text    = files.getText(uri)
    local message = lang.script('PARSER_'..err.type, err.info)

    if err.version then
        local version = err.info and err.info.version or config.config.runtime.version
        message = message .. ('(%s)'):format(lang.script('DIAG_NEED_VERSION'
            , concat(err.version, '/')
            , version
        ))
    end

    local related = err.info and err.info.related
    local relatedInformation
    if related then
        relatedInformation = {}
        for _, rel in ipairs(related) do
            local rmessage
            if rel.message then
                rmessage = lang.script('PARSER_'..rel.message)
            else
                rmessage = text:sub(rel.start, rel.finish)
            end
            local relUri = files.getOriginUri(rel.uri)
            relatedInformation[#relatedInformation+1] = {
                message  = rmessage,
                location = define.location(relUri, files.range(relUri, rel.start, rel.finish)),
            }
        end
    end

    return {
        code     = err.type:lower():gsub('_', '-'),
        range    = files.range(uri, err.start, err.finish),
        severity = define.DiagnosticSeverity.Error,
        source   = lang.script.DIAG_SYNTAX_CHECK,
        message  = message,
        relatedInformation = relatedInformation,
    }
end

local function buildDiagnostic(uri, diag)
    if not files.exists(uri) then
        return
    end

    local relatedInformation
    if diag.related then
        relatedInformation = {}
        for _, rel in ipairs(diag.related) do
            local rtext  = files.getText(rel.uri)
            relatedInformation[#relatedInformation+1] = {
                message  = rel.message or rtext:sub(rel.start, rel.finish),
                location = define.location(rel.uri, files.range(rel.uri, rel.start, rel.finish))
            }
        end
    end
    local code = diag.code
    local source = lang.script.DIAG_DIAGNOSTICS
    if code == "type-checking" then
        source = lang.script.DIAG_TYPECHECKING
        code = nil
    end
    return {
        range    = files.range(uri, diag.start, diag.finish),
        source   = source,
        severity = diag.level,
        message  = diag.message,
        code     = code,
        tags     = diag.tags,
        data     = diag.data,
        relatedInformation = relatedInformation,
    }
end

local function mergeSyntaxAndDiags(a, b)
    if not a and not b then
        return nil
    end
    local count = 0
    local t = {}
    if a then
        for i = 1, #a do
            local severity = a[i].severity
            if severity == define.DiagnosticSeverity.Hint
            or severity == define.DiagnosticSeverity.Information then
                t[#t+1] = a[i]
            elseif count < 10000 then
                count = count + 1
                t[#t+1] = a[i]
            end
        end
    end
    if b then
        for i = 1, #b do
            local severity = b[i].severity
            if severity == define.DiagnosticSeverity.Hint
            or severity == define.DiagnosticSeverity.Information then
                t[#t+1] = b[i]
            elseif count < 10000 then
                count = count + 1
                t[#t+1] = b[i]
            end
        end
    end
    return t
end

function m.clear(uri)
    local luri = files.asKey(uri)
    if not m.cache[luri] then
        return
    end
    m.cache[luri] = nil
    proto.notify('textDocument/publishDiagnostics', {
        uri = files.getOriginUri(luri) or uri,
        diagnostics = {},
    })
    log.debug('clearDiagnostics', files.getOriginUri(uri))
end

function m.clearAll()
    for luri in pairs(m.cache) do
        m.clear(luri)
    end
end

function m.syntaxErrors(uri, ast)
    if not config.config.diagnostics.enable then
        return nil
    end
    if #ast.errs == 0 then
        return nil
    end

    local results = {}

    for _, err in ipairs(ast.errs) do
        if not config.config.diagnostics.disable[err.type:lower():gsub('_', '-')] then
            results[#results+1] = buildSyntaxError(uri, err)
        end
    end

    return results
end

function m.diagnostics(uri, diags)
    if not m._start then
        return
    end

    if not ws.isReady() then
        return
    end

    core(uri, function (results)
        if #results == 0 then
            return
        end
        for i = 1, #results do
            diags[#diags+1] = buildDiagnostic(uri, results[i])
        end
    end)
end

function m.doDiagnostic(uri)
    uri = files.asKey(uri)
    if (files.isLibrary(uri) or ws.isIgnored(uri))
    and not files.isOpen(uri) then
        return
    end

    await.delay()

    local ast = files.getAst(uri)
    if not ast then
        m.clear(uri)
        return
    end

    local prog <close> = progress.create(lang.script.WINDOW_DIAGNOSING, 0.5)
    prog:setMessage(ws.getRelativePath(files.getOriginUri(uri)))

    local syntax = m.syntaxErrors(uri, ast)
    local diags = {}
    local function pushResult()
        tracy.ZoneBeginN 'mergeSyntaxAndDiags'
        local _ <close> = tracy.ZoneEnd
        local full = mergeSyntaxAndDiags(syntax, diags)
        if not full then
            m.clear(uri)
            return
        end

        if util.equal(m.cache[uri], full) then
            return
        end
        m.cache[uri] = full

        proto.notify('textDocument/publishDiagnostics', {
            uri = files.getOriginUri(uri),
            diagnostics = full,
        })
        if #full > 0 then
            log.debug('publishDiagnostics', files.getOriginUri(uri), #full)
        end
    end

    if await.hasID 'diagnosticsAll' then
        m.checkStepResult = nil
    else
        local clock = os.clock()
        m.checkStepResult = function ()
            if os.clock() - clock >= 0.2 then
                pushResult()
                clock = os.clock()
            end
        end
    end

    m.diagnostics(uri, diags)
    pushResult()
    m.checkStepResult = nil
    return #ast.errs == 0
end

function m.refresh(uri, diagRequires)
    if not m._start then
        return
    end
    await.call(function ()
        await.delay()
        if uri then
            if m.doDiagnostic(uri) and not m.diagnosingAll and diagRequires then
                m.diagnosticsRequires(uri)
            end
        end
    end, 'files.version')
end

local function askForDisable()
    if m.dontAskedForDisable then
        return
    end
    local delay = 30
    local delayTitle = lang.script('WINDOW_DELAY_WS_DIAGNOSTIC', delay)
    local item = proto.awaitRequest('window/showMessageRequest', {
        type    = define.MessageType.Info,
        message = lang.script.WINDOW_SETTING_WS_DIAGNOSTIC,
        actions = {
            {
                title = lang.script.WINDOW_DONT_SHOW_AGAIN,
            },
            {
                title = delayTitle,
            },
            {
                title = lang.script.WINDOW_DISABLE_DIAGNOSTIC,
            },
        }
    })
    if not item then
        return
    end
    if     item.title == lang.script.WINDOW_DONT_SHOW_AGAIN then
        m.dontAskedForDisable = true
    elseif item.title == delayTitle then
        proto.notify('$/command', {
            command   = 'lua.config',
            data      = {
                key    = 'robloxLsp.diagnostics.workspaceDelay',
                action = 'set',
                value  = delay * 1000,
            }
        })
    elseif item.title == lang.script.WINDOW_DISABLE_DIAGNOSTIC then
        proto.notify('$/command', {
            command   = 'lua.config',
            data      = {
                key    = 'robloxLsp.diagnostics.workspaceDelay',
                action = 'set',
                value  = -1,
            }
        })
    end
end

function m.diagnosticsRequires(reqUri)
    if (ws.isIgnored(reqUri) and not files.isOpen(reqUri)) then
        return
    end
    if not m._start then
        return
    end
    local delay = config.config.diagnostics.workspaceDelay / 1000
    if delay < 0 then
        return
    end
    await.close 'diagnosticsAll'
    await.call(function ()
        await.sleep(delay)
        m.diagnosticsAllClock = os.clock()
        local clock = os.clock()
        local bar <close> = progress.create(lang.script.WORKSPACE_DIAGNOSTIC, 1)
        local cancelled
        bar:onCancel(function ()
            log.debug('Cancel workspace diagnostics')
            cancelled = true
            askForDisable()
        end)
        local uris = files.getRequiring(reqUri, true)
        for i, uri in ipairs(uris) do
            bar:setMessage(('%d/%d'):format(i, #uris))
            bar:setPercentage(i / #uris * 100)
            m.doDiagnostic(uri)
            await.delay()
            if cancelled then
                log.debug('Break workspace diagnostics')
                break
            end
        end
        bar:remove()
        log.debug('全文诊断耗时：', os.clock() - clock)
    end, 'files.version', 'diagnosticsAll')
end

function m.diagnosticsAll()
    if not config.config.diagnostics.enable then
        m.clearAll()
    end
    if not m._start then
        return
    end
    local delay = config.config.diagnostics.workspaceDelay / 1000
    if delay < 0 then
        return
    end
    await.close 'diagnosticsAll'
    await.call(function ()
        await.sleep(delay)
        m.diagnosingAll = true
        m.diagnosticsAllClock = os.clock()
        local clock = os.clock()
        local bar <close> = progress.create(lang.script.WORKSPACE_DIAGNOSTIC, 1)
        local cancelled
        bar:onCancel(function ()
            log.debug('Cancel workspace diagnostics')
            cancelled = true
            askForDisable()
        end)
        local uris = files.getAllUris()
        for i, uri in ipairs(uris) do
            bar:setMessage(('%d/%d'):format(i, #uris))
            bar:setPercentage(i / #uris * 100)
            m.doDiagnostic(uri)
            await.delay()
            if cancelled then
                log.debug('Break workspace diagnostics')
                break
            end
        end
        bar:remove()
        log.debug('全文诊断耗时：', os.clock() - clock)
        m.diagnosingAll = false
    end, 'files.version', 'diagnosticsAll')
end

function m.start()
    m._start = true
    m.diagnosticsAll()
end

function m.pause()
    m._start = false
    await.close 'diagnosticsAll'
end

function m.checkStepResult()
    if await.hasID 'diagnosticsAll' then
        return
    end
end

function m.checkWorkspaceDiag()
    if not await.hasID 'diagnosticsAll' then
        return
    end
    local speedRate = config.config.diagnostics.workspaceRate
    if speedRate <= 0 or speedRate >= 100 then
        return
    end
    local currentClock = os.clock()
    local passed = currentClock - m.diagnosticsAllClock
    local sleepTime = passed * (100 - speedRate) / speedRate + m.sleepRest
    m.sleepRest = 0.0
    if sleepTime < 0.001 then
        m.sleepRest = m.sleepRest + sleepTime
        return
    end
    if sleepTime > 0.1 then
        m.sleepRest = sleepTime - 0.1
        sleepTime = 0.1
    end
    await.sleep(sleepTime)
    m.diagnosticsAllClock = os.clock()
    return false
end

files.watch(function (ev, uri)
    if ev == 'remove' then
        m.clear(uri)
        m.refresh(uri)
    elseif ev == 'update' then
        if ws.isReady() then
            m.refresh(uri)
        end
    -- elseif ev == 'open' then
    --     if ws.isReady() then
    --         m.doDiagnostic(uri)
    --     end
    elseif ev == 'close' then
        if files.isLibrary(uri)
        or ws.isIgnored(uri) then
            m.clear(uri)
        end
    elseif ev == 'save' then
        if ws.isReady() then
            m.refresh(uri, true)
        end
    end
end)

await.watch(function (ev, co)
    if ev == 'delay' then
        if m.checkStepResult then
            m.checkStepResult()
        end
        return m.checkWorkspaceDiag()
    end
end)

return m
