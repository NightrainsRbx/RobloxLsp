local files   = require 'files'
local lang    = require 'language'
local guide   = require 'core.guide'
local util    = require 'utility'
local sp      = require 'bee.subprocess'
local vm      = require 'vm'
local config  = require 'config'
local rbximports = require 'core.module-import'

local function checkDisableByLuaDocExits(uri, row, mode, code)
    local lines = files.getLines(uri)
    local ast   = files.getAst(uri)
    local text  = files.getOriginText(uri)
    local line  = lines[row]
    if ast.ast.docs and line then
        for _, doc in ipairs(ast.ast.docs) do
            if  doc.start >= line.start
            and doc.finish <= line.finish then
                if doc.type == 'doc.diagnostic' then
                    if doc.mode == mode then
                        if doc.names then
                            return {
                                start   = doc.finish,
                                finish  = doc.finish,
                                newText = text:sub(doc.finish, doc.finish)
                                        .. ', '
                                        .. code
                            }
                        else
                            return {
                                start   = doc.finish,
                                finish  = doc.finish,
                                newText = text:sub(doc.finish, doc.finish)
                                        .. ': '
                                        .. code
                            }
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function checkDisableByLuaDocInsert(uri, row, mode, code)
    local lines = files.getLines(uri)
    local ast   = files.getAst(uri)
    local text  = files.getOriginText(uri)
    -- 先看看上一行是不是已经有了
    -- 没有的话就插入一行
    local line = lines[row]
    return {
        start   = line.start,
        finish  = line.start,
        newText = '---@diagnostic ' .. mode .. ': ' .. code .. '\n'
                .. text:sub(line.start, line.start)
    }
end

local function disableDiagnostic(uri, code, start, results)
    if code == "type-checking" then
        return
    end
    local lines = files.getLines(uri)
    local row   = guide.positionOf(lines, start)
    results[#results+1] = {
        title   = lang.script('ACTION_DISABLE_DIAG', code),
        kind    = 'quickfix',
        command = {
            title    = lang.script.COMMAND_DISABLE_DIAG,
            command  = 'lua.config',
            arguments = {
                {
                    key    = 'robloxLsp.diagnostics.disable',
                    action = 'add',
                    value  = code,
                    uri    = uri,
                }
            }
        }
    }
    local function pushEdit(title, edit)
        results[#results+1] = {
            title   = title,
            kind    = 'quickfix',
            edit    = {
                changes = {
                    [uri] = { edit }
                }
            }
        }
    end

    pushEdit(lang.script('ACTION_DISABLE_DIAG_LINE', code),
           checkDisableByLuaDocExits (uri, row - 1, 'disable-next-line', code)
        or checkDisableByLuaDocInsert(uri, row,     'disable-next-line', code))
    pushEdit(lang.script('ACTION_DISABLE_DIAG_FILE', code),
           checkDisableByLuaDocExits (uri, 1,   'disable',           code)
        or checkDisableByLuaDocInsert(uri, 1,   'disable',           code))
end

local function markGlobal(uri, name, results)
    results[#results+1] = {
        title   = lang.script('ACTION_MARK_GLOBAL', name),
        kind    = 'quickfix',
        command = {
            title     = lang.script.COMMAND_MARK_GLOBAL,
            command   = 'lua.config',
            arguments = {
                {
                    key    = 'robloxLsp.diagnostics.globals',
                    action = 'add',
                    value  = name,
                    uri    = uri,
                }
            }
        }
    }
end

local function changeVersion(uri, version, results)
    results[#results+1] = {
        title   = lang.script('ACTION_RUNTIME_VERSION', version),
        kind    = 'quickfix',
        command = {
            title     = lang.script.COMMAND_RUNTIME_VERSION,
            command   = 'lua.config',
            arguments = {
                {
                    key    = 'robloxLsp.runtime.version',
                    action = 'set',
                    value  = version,
                    uri    = uri,
                }
            }
        },
    }
end

local function suggestImport(uri, path, results, edit)
    results[#results + 1] = {
        title = lang.script('ACTION_IMPORT_SUGGESTED', path:gsub("^game%.", "")),
        kind = 'quickfix',
        edit = edit,
        data = {
            id = path
        }
    }
end

local function solveSuggestedImport(uri, diag, results)
    local ast    = files.getAst(uri)
    local offset = files.offsetOfWord(uri, diag.range["end"])
    local name = guide.eachSourceContain(ast.ast, offset, function (source)
        if source.type == "type.name" then
            return source[1]
        end
        if source.type ~= 'getglobal' then
            return
        end

        return guide.getKeyName(source)
    end)

    local matches = rbximports.findPotentialImportsSorted(uri, name, ast, offset)

    local paths = {}
    for _, match in ipairs(matches) do
        if config.config.suggestedImports.importPathType == "Both" then
            if match.absoluteLuaPath then
                paths[#paths+1] = match.absoluteLuaPath
            end
            if match.relativeLuaPath then
                paths[#paths+1] = match.relativeLuaPath
            end
        elseif config.config.suggestedImports.importPathType == "Shortest First" then
            if match.relativeLuaPath and match.absoluteLuaPath then
                if #match.relativeLuaPath < #match.absoluteLuaPath then
                    paths[#paths+1] = match.relativeLuaPath
                else
                    paths[#paths+1] = match.absoluteLuaPath
                end
            else
                paths[#paths+1] = match.relativeLuaPath or match.absoluteLuaPath
            end
        else
            paths[#paths+1] = match.relativeLuaPath or match.absoluteLuaPath
        end
    end

    if config.config.suggestedImports.importPathType == "Shortest First" then
        table.sort(paths)
    end

    for index, path in ipairs(paths) do
        if index > 10 then
            break
        end
        if rbximports.resolveCallback[path] then
            suggestImport(uri, path, results)
        else
            suggestImport(uri, path, results, {
                changes = {
                    [uri] = {
                        [1] = rbximports.buildInsertRequire(ast, offset, name, path)
                    }
                }
            })
        end
    end
end

local function solveUndefinedGlobal(uri, diag, results)
    local ast    = files.getAst(uri)
    local offset = files.offsetOfWord(uri, diag.range.start)
    guide.eachSourceContain(ast.ast, offset, function (source)
        if source.type ~= 'getglobal' then
            return
        end

        local name = guide.getKeyName(source)
        markGlobal(uri, name, results)
    end)

    if diag.data and diag.data.versions then
        for _, version in ipairs(diag.data.versions) do
            changeVersion(uri, version, results)
        end
    end
end

local function solveLowercaseGlobal(uri, diag, results)
    local ast    = files.getAst(uri)
    local offset = files.offsetOfWord(uri, diag.range.start)
    guide.eachSourceContain(ast.ast, offset, function (source)
        if source.type ~= 'setglobal' then
            return
        end

        local name = guide.getKeyName(source)
        markGlobal(uri, name, results)
    end)
end

local function findSyntax(uri, diag)
    local ast = files.getAst(uri)
    for _, err in ipairs(ast.errs) do
        if err.type:lower():gsub('_', '-') == diag.code then
            local range = files.range(uri, err.start, err.finish)
            if util.equal(range, diag.range) then
                return err
            end
        end
    end
    return nil
end

local function solveSyntaxByChangeVersion(uri, err, results)
    if type(err.version) == 'table' then
        for _, version in ipairs(err.version) do
            changeVersion(uri, version, results)
        end
    else
        changeVersion(uri, err.version, results)
    end
end

local function solveSyntaxByAddDoEnd(uri, err, results)
    local text   = files.getText(uri)
    results[#results+1] = {
        title = lang.script.ACTION_ADD_DO_END,
        kind = 'quickfix',
        edit = {
            changes = {
                [uri] = {
                    {
                        start   = err.start,
                        finish  = err.finish,
                        newText = ('do %s end'):format(text:sub(err.start, err.finish)),
                    },
                }
            }
        }
    }
end

local function solveSyntaxByFix(uri, err, results)
    local changes = {}
    for _, fix in ipairs(err.fix) do
        changes[#changes+1] = {
            start   = fix.start,
            finish  = fix.finish,
            newText = fix.text,
        }
    end
    results[#results+1] = {
        title = lang.script('ACTION_' .. err.fix.title, err.fix),
        kind  = 'quickfix',
        edit = {
            changes = {
                [uri] = changes,
            }
        }
    }
end

local function solveSyntax(uri, diag, results)
    local err = findSyntax(uri, diag)
    if not err then
        return
    end
    if err.version then
        solveSyntaxByChangeVersion(uri, err, results)
    end
    if err.type == 'ACTION_AFTER_BREAK' or err.type == 'ACTION_AFTER_RETURN' then
        solveSyntaxByAddDoEnd(uri, err, results)
    end
    if err.fix then
        solveSyntaxByFix(uri, err, results)
    end
end

local function solveNewlineCall(uri, diag, results)
    local start   = files.unrange(uri, diag.range)
    results[#results+1] = {
        title = lang.script.ACTION_ADD_SEMICOLON,
        kind = 'quickfix',
        edit = {
            changes = {
                [uri] = {
                    {
                        start  = start,
                        finish = start,
                        newText = ';',
                    }
                }
            }
        }
    }
end

local function solveAmbiguity1(uri, diag, results)
    results[#results+1] = {
        title = lang.script.ACTION_ADD_BRACKETS,
        kind = 'quickfix',
        command = {
            title = lang.script.COMMAND_ADD_BRACKETS,
            command = 'lua.solve:' .. sp:get_id(),
            arguments = {
                {
                    name  = 'ambiguity-1',
                    uri   = uri,
                    range = diag.range,
                }
            }
        },
    }
end

local function solveTrailingSpace(uri, diag, results)
    results[#results+1] = {
        title = lang.script.ACTION_REMOVE_SPACE,
        kind = 'quickfix',
        command = {
            title = lang.script.COMMAND_REMOVE_SPACE,
            command = 'lua.removeSpace:' .. sp:get_id(),
            arguments = {
                {
                    uri = uri,
                }
            }
        },
    }
end

local function solveDiagnostic(uri, diag, start, results)
    if diag.source == lang.script.DIAG_SYNTAX_CHECK then
        solveSyntax(uri, diag, results)
        return
    end
    if not diag.code then
        return
    end
    if     diag.code == 'undefined-global' then
        solveUndefinedGlobal(uri, diag, results)
    elseif diag.code == 'suggested-import' then
        solveSuggestedImport(uri, diag, results)
    elseif diag.code == 'lowercase-global' then
        solveLowercaseGlobal(uri, diag, results)
    elseif diag.code == 'newline-call' then
        solveNewlineCall(uri, diag, results)
    elseif diag.code == 'ambiguity-1' then
        solveAmbiguity1(uri, diag, results)
    elseif diag.code == 'trailing-space' then
        solveTrailingSpace(uri, diag, results)
    end

    if config.config.diagnostics.enable and diag.code ~= 'suggested-import' then
        disableDiagnostic(uri, diag.code, start, results)
    end
end

local function checkQuickFix(results, uri, start, diagnostics)
    if not diagnostics then
        return
    end
    for _, diag in ipairs(diagnostics) do
        solveDiagnostic(uri, diag, start, results)
    end
end

local function checkSwapParams(results, uri, start, finish)
    local ast  = files.getAst(uri)
    local text = files.getText(uri)
    if not ast then
        return
    end
    local args = {}
    guide.eachSourceBetween(ast.ast, start, finish, function (source)
        if source.type == 'callargs'
        or source.type == 'funcargs' then
            local targetIndex
            for index, arg in ipairs(source) do
                if arg.start - 1 <= finish and arg.finish >= start then
                    -- should select only one param
                    if targetIndex then
                        return
                    end
                    targetIndex = index
                end
            end
            if not targetIndex then
                return
            end
            local node
            if source.type == 'callargs' then
                node = text:sub(source.parent.node.start, source.parent.node.finish)
            elseif source.type == 'funcargs' then
                local var = source.parent.parent
                if vm.isSet(var) then
                    node = text:sub(var.start, var.finish)
                else
                    node = lang.script.SYMBOL_ANONYMOUS
                end
            end
            args[#args+1] = {
                source = source,
                index  = targetIndex,
                node   = node,
            }
        end
    end)
    if #args == 0 then
        return
    end
    table.sort(args, function (a, b)
        return a.source.start > b.source.start
    end)
    local target = args[1]
    uri = files.getOriginUri(uri)
    local myArg = target.source[target.index]
    for i, targetArg in ipairs(target.source) do
        if i ~= target.index then
            results[#results+1] = {
                title = lang.script('ACTION_SWAP_PARAMS', {
                    node  = target.node,
                    index = i,
                }),
                kind = 'refactor.rewrite',
                edit = {
                    changes = {
                        [uri] = {
                            {
                                start   = myArg.start,
                                finish  = myArg.finish,
                                newText = text:sub(targetArg.start, targetArg.finish),
                            },
                            {
                                start   = targetArg.start,
                                finish  = targetArg.finish,
                                newText = text:sub(myArg.start, myArg.finish),
                            },
                        }
                    }
                }
            }
        end
    end
end

--local function checkExtractAsFunction(results, uri, start, finish)
--    local ast = files.getAst(uri)
--    local text = files.getText(uri)
--    local funcs = {}
--    guide.eachSourceContain(ast.ast, start, function (source)
--        if source.type == 'function'
--        or source.type == 'main' then
--            funcs[#funcs+1] = source
--        end
--    end)
--    table.sort(funcs, function (a, b)
--        return a.start > b.start
--    end)
--    local func = funcs[1]
--    if not func then
--        return
--    end
--    if #func == 0 then
--        return
--    end
--    if func.finish < finish then
--        return
--    end
--    local actions = {}
--    for i = 1, #func do
--        local action = func[i]
--        if  action.start  < start
--        and action.finish > start then
--            return
--        end
--        if  action.start  < finish
--        and action.finish > finish then
--            return
--        end
--        if  action.finish >= start
--        and action.start  <= finish then
--            actions[#actions+1] = action
--        end
--    end
--    if text:sub(start, actions[1].start - 1):find '[%C%S]' then
--        return
--    end
--    if text:sub(actions[1].finish + 1, finish):find '[%C%S]' then
--        return
--    end
--    while func do
--        local funcName = getExtractFuncName(uri, actions[1].start)
--        local funcParams = getExtractFuncParams(uri, actions[1].start)
--        results[#results+1] = {
--            title = lang.script('ACTION_EXTRACT'),
--            kind = 'refactor.extract',
--            edit = {
--                changes = {
--                    [uri] = {
--                        {
--                            start   = actions[1].start,
--                            finish  = actions[1].start - 1,
--                            newText = text:sub(targetArg.start, targetArg.finish),
--                        },
--                        {
--                            start   = targetArg.start,
--                            finish  = targetArg.finish,
--                            newText = text:sub(myArg.start, myArg.finish),
--                        },
--                    }
--                }
--            }
--        }
--        func = guide.getParentFunction(func)
--    end
--end

local function checkJsonToLua(results, uri, start, finish)
    local text = files.getText(uri)
    local jsonStart = text:match ('()[%{%[]', start)
    if not jsonStart then
        return
    end
    local jsonFinish
    for i = math.min(finish, #text), jsonStart + 1, -1 do
        local char = text:sub(i, i)
        if char == ']'
        or char == '}' then
            jsonFinish = i
            break
        end
    end
    if not jsonFinish then
        return
    end
    if not text:sub(jsonStart, jsonFinish):find '"%s*%:' then
        return
    end
    results[#results+1] = {
        title = lang.script.ACTION_JSON_TO_LUA,
        kind = 'refactor.rewrite',
        command = {
            title = lang.script.COMMAND_JSON_TO_LUA,
            command = 'lua.jsonToLua:' .. sp:get_id(),
            arguments = {
                {
                    uri    = uri,
                    start  = jsonStart,
                    finish = jsonFinish,
                }
            }
        },
    }
end

local function codeAction(uri, start, finish, diagnostics)
    local ast = files.getAst(uri)
    if not ast then
        return nil
    end

    local results = {}

    checkQuickFix(results, uri, start, diagnostics)
    checkSwapParams(results, uri, start, finish)
    --checkExtractAsFunction(results, uri, start, finish)
    checkJsonToLua(results, uri, start, finish)

    return results
end

local function resolve(id)
    if rbximports.resolveCallback[id] then
        return rbximports.resolveCallback[id]()
    end
end

return {
    codeAction = codeAction,
    resolve = resolve
}
