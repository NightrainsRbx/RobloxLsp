local mt = require 'vm.manager'
local library = require 'vm.library'

---@param func emmyFunction
function mt:callIpairs(func, values, source)
    local tbl = values[1]
    func:setReturn(1, library.special['@ipairs'])
    func:setReturn(2, tbl)
end

---@param func emmyFunction
function mt:callAtIpairs(func, values, source)
    local tbl = values[1]
    if tbl then
        local emmy = tbl:getEmmy()
        if emmy then
            if emmy.type == 'emmy.arrayType' then
                local value = self:createLibValue(emmy:getName(), source)
                func:setReturn(2, value)
            end
        end
    end
end

---@param func emmyFunction
function mt:callPairs(func, values, source)
    local tbl = values[1]
    func:setReturn(1, library.special['next'])
    func:setReturn(2, tbl)
end

---@param func emmyFunction
function mt:callNext(func, values, source)
    local tbl = values[1]
    if tbl then
        local key_index = 1
        local value_index = 2
        local emmy = tbl:getEmmy()
        if emmy then
            if emmy.type == 'emmy.arrayType' then
                local key = self:createValue('integer', source)
                local value = self:createLibValue(emmy:getName(), source)
                func:setReturn(key_index, key)
                func:setReturn(value_index, value)
            elseif emmy.type == 'emmy.tableType' then
                local key = self:createLibValue(emmy:getKeyType():getType(), source)
                local value = self:createLibValue(emmy:getValueType():getType(), source)
                func:setReturn(key_index, key)
                func:setReturn(value_index, value)
            end
        else
            local tp = tbl:getType()
            local special = tp:match("%<[%w%.]+%>")
            if special then
                tp = tp:sub(1, #tp - #special)
                special = special:sub(2, #special - 1)
            end
            if tp == "Objects" then
                local key = self:createValue('integer', source)
                local value = self:createLibValue(special or 'Instance', source)
                func:setReturn(key_index, key)
                func:setReturn(value_index, value)
            elseif tp == "Array" then
                local key = self:createValue('integer', source)
                func:setReturn(key_index, key)
                if special then
                    local value = self:createLibValue(special, source)
                    func:setReturn(value_index, value)
                end
            elseif tp == "Dictionary" then
                local key = self:createValue('string', source)
                func:setReturn(key_index, key)
                if special then
                    local value = self:createLibValue(special, source)
                    func:setReturn(value_index, value)
                end
            end
        end
    end
end