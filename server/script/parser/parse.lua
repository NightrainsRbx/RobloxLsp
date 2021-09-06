local ast = require 'parser.ast'

<<<<<<< HEAD
local Errs
local State

local function pushError(err)
    if err.finish < err.start then
        err.finish = err.start
    end
    local last = Errs[#Errs]
    if last then
        if last.start <= err.start and last.finish >= err.finish then
            return
        end
    end
    err.level = err.level or 'error'
    Errs[#Errs+1] = err
    return err
end

return function (self, lua, mode, version)
    Errs = {}
    State= {
        Break = 0,
        Label = {{}},
        Dots = {true},
        Version = version,
        Comments = {},
        MissedEnd = {},
        Lua = lua,
    }
    ast.init(State, Errs)
    local suc, res, err = xpcall(self.grammar, debug.traceback, self, lua, mode)
    if not suc then
        return nil, res
    end
    if not res then
        pushError(err)
        return nil, Errs
    end
    if #res > 0 and type(res[#res]) == "table" then
        res[#res].last = true
    end
    return res, Errs, State.Comments, State.MissedEnd
=======
return function (self, lua, mode, options)
    local errs  = {}
    local diags = {}
    local comms = {}
    local state = {
        lua = lua,
        root = {},
        errs = errs,
        diags = diags,
        comms = comms,
        options = options or {},
        pushError = function (err)
            if err.finish < err.start then
                err.finish = err.start
            end
            local last = errs[#errs]
            if last then
                if last.start <= err.start and last.finish >= err.finish then
                    return
                end
            end
            err.level = err.level or 'error'
            errs[#errs+1] = err
            return err
        end,
        pushDiag = function (code, info)
            if not diags[code] then
                diags[code] = {}
            end
            diags[code][#diags[code]+1] = info
        end,
        pushComment = function (comment)
            comms[#comms+1] = comment
        end
    }
    local clock = os.clock()
    ast.init(state)
    local suc, res, err = xpcall(self.grammar, debug.traceback, self, lua, mode)
    ast.close()
    if not suc then
        return nil, res
    end
    if not res and err then
        state.pushError(err)
    end
    state.ast = res
    state.parseClock = os.clock() - clock
    return state
>>>>>>> origin/master
end
