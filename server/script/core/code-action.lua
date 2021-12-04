local files   = require 'files'
local lang    = require 'language'
local define  = require 'proto.define'
local guide   = require 'core.guide'
local util    = require 'utility'
local sp      = require 'bee.subprocess'
local vm      = require 'vm'
local rbxlibs = require 'library.rbxlibs'
local config  = require 'config'
local glob    = require 'glob'
local furi     = require 'file-uri'

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

local function findMatchingScripts(name, object, matching, path, ignoreGlob)
    object = object or rbxlibs.global.game
    matching = matching or {}
    path = path or { object }

    if not ignoreGlob then
        if config.config.diagnostics.importIgnore[1] then
            ignoreGlob = glob.glob(config.config.diagnostics.importIgnore, { ignoreCase = false })
        else
            ignoreGlob = function(_)
                return false
            end
        end
    end

    for _, child in pairs(object.value.child) do
        if child.name ~= 'Parent' then
            if child.name == name and child.type == 'type.library' and child.value[1] == 'ModuleScript' then
                if not ignoreGlob(furi.decode(child.value.uri)) then
                    local pathCopy = util.shallowCopy(path)
                    table.insert(pathCopy, child)

                    table.insert(matching, {
                        object = child.value,
                        path = pathCopy,
                    })
                end
            end
            if child.type == 'type.library' and child.value.child then
                table.insert(path, child)
                findMatchingScripts(name, child, matching, path, ignoreGlob)
                table.remove(path)
            end
        end
    end

    return matching
end

local function findPath(uri, object, path)
    object = object or rbxlibs.global.game
    path = path or { object }

    for _, child in pairs(object.value.child) do
        if child.name ~= 'Parent' then
            if child.type == 'type.library' and child.value.uri == uri then
                table.insert(path, child)
                return path
            end

            if child.type == 'type.library' and child.value.child then
                table.insert(path, child)
                local result = findPath(uri, child, path)
                if result then
                    return result
                end
                table.remove(path)
            end
        end
    end
end

local function getSafeIndexer(name)
    if name:match('^%D[%w_]*$') then
        return '.' .. name
    else
        return string.format('[%q]', name)
    end
end

local function canIndexObject(object)
    if not config.config.diagnostics.importScriptChildren then
        if object.value[1]:match("Script$") then
            return false
        end
    end

    return true
end

local function findRelativeLuaPath(sourcePath, targetPath)
    local sourcePathMap = {}
    for index, node in ipairs(sourcePath) do
        -- We only want to use relative paths if they don't go through game or a
        -- service
        local isGame = node == rbxlibs.global.game
        local isChildOfGame = node.value.child and node.value.child.Parent == rbxlibs.global.game
        if not isGame and not isChildOfGame then
            sourcePathMap[node] = index
        end
    end

    local commonAncestor
    local commonAncestorTargetIndex
    for index = #targetPath, 1, -1 do
        local node = targetPath[index]
        if sourcePathMap[node] then
            commonAncestor = node
            commonAncestorTargetIndex = index
            break
        end
    end

    if not commonAncestor then
        return
    end

    local builder = {'script'}

    for _ = #sourcePath - 1, sourcePathMap[commonAncestor], -1 do
        table.insert(builder, '.Parent')
    end

    for index = commonAncestorTargetIndex + 1, #targetPath do
        local node = targetPath[index]
        
        if index ~= #targetPath and not canIndexObject(node) then
            return
        end

        table.insert(builder, getSafeIndexer(node.name))
    end

    return table.concat(builder)
end

local function getAbsoluteLuaPath(path)
    local builder = { path[1].name }

    for index, node in ipairs(path) do
        if index ~= 1 then
            if not canIndexObject(node) then
                return
            end

            table.insert(builder, getSafeIndexer(node.name))
        end
    end

    return table.concat(builder)
end

local function solveUndefinedGlobalImport(uri, diag, results)
    local ast    = files.getAst(uri)
    local offset = files.offsetOfWord(uri, diag.range.start)
    local name = guide.eachSourceContain(ast.ast, offset, function (source)
        if source.type ~= 'getglobal' then
            return
        end

        return guide.getKeyName(source)
    end)

    local rawMatches = findMatchingScripts(name)
    if rawMatches[1] == nil then
        return
    end

    local sourcePath = findPath(uri)
    
    local matches = {}
    for _, match in ipairs(rawMatches) do
        -- Never do `require(script)` or equivalent.
        if match.object.uri ~= uri then
            local targetPath = match.path
            match.relativeLuaPath = sourcePath and findRelativeLuaPath(sourcePath, targetPath)
            match.absoluteLuaPath = getAbsoluteLuaPath(targetPath)
            -- If the path tries to index into a script and that's disallowed,
            -- it won't have any paths available
            if match.relativeLuaPath or match.absoluteLuaPath then
                table.insert(matches, match)
            end
        end
    end
    
    -- Relative-available matches first, sorted by smallest lua path string,
    -- followed by absolute paths, sorted by smallest lua path string
    table.sort(matches, function(a, b)
        if a.relativeLuaPath and b.relativeLuaPath then
            return a.relativeLuaPath < b.relativeLuaPath
        elseif a.relativeLuaPath or b.relativeLuaPath then
            return a.relativeLuaPath ~= nil
        else
            return a.absoluteLuaPath < b.absoluteLuaPath
        end
    end)

    for index, match in ipairs(matches) do
        -- Don't display too many results if we found many matches
        if index > 10 then
            break
        end

        local luaPath = match.relativeLuaPath or match.absoluteLuaPath

        results[#results+1] = {
            title = lang.script('ACTION_IMPORT_SUGGESTED', luaPath),
            kind = 'quickfix',
            edit = {
                changes = {
                    [uri] = {
                        {
                            start   = 1,
                            finish  = 0,
                            newText = ('local %s = require(%s)\n'):format(name, luaPath),
                        },
                    }
                }
            }
        }
    end
end

local function solveUndefinedGlobal(uri, diag, results)
    solveUndefinedGlobalImport(uri, diag, results)

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
    elseif diag.code == 'lowercase-global' then
        solveLowercaseGlobal(uri, diag, results)
    elseif diag.code == 'newline-call' then
        solveNewlineCall(uri, diag, results)
    elseif diag.code == 'ambiguity-1' then
        solveAmbiguity1(uri, diag, results)
    elseif diag.code == 'trailing-space' then
        solveTrailingSpace(uri, diag, results)
    end
    disableDiagnostic(uri, diag.code, start, results)
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

return function (uri, start, finish, diagnostics)
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
