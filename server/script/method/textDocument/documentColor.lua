local function getRange(start, finish, lines)
    local start_row,  start_col  = lines:rowcol(start)
    local finish_row, finish_col = lines:rowcol(finish)
    return {
        start = {
            line = start_row - 1,
            character = start_col - 1,
        },
        ['end'] = {
            line = finish_row - 1,
            -- 这里不用-1，因为前端期待的是匹配完成后的位置
            character = finish_col,
        },
    }
end

local function hsvToRgb(h, s, v, a)
    local r, g, b

    local i = math.floor(h * 6);
    local f = h * 6 - i;
    local p = v * (1 - s);
    local q = v * (1 - f * s);
    local t = v * (1 - (1 - f) * s);

    i = i % 6

    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    elseif i == 5 then r, g, b = v, p, q
    end

    return r, g, b
end

local COLOR3_CONSTRUCTORS = {
    ["new"] = true,
    ["fromRGB"] = true,
    ["fromHSV"] = true
}

--- @param lsp LSP
--- @param params table
--- @return table
return function (lsp, params)
    local vm, lines = lsp:getVM(params.textDocument.uri)
    if not vm then
        return
    end
    local results = {}
    vm:eachSource(function(source)
        if source.type ~= "call" then
            return
        end
        local simple = source:get 'simple'
        if not simple then
            return
        end
        if #simple == 4 and simple[1][1] == "Color3" then
            local funcName = simple[3][1]
            local callArgs = simple[4]
            if COLOR3_CONSTRUCTORS[funcName] then
                local rgb = {}
                for _, arg in ipairs(callArgs) do
                    local number = vm:getArgNumber(arg)
                    if number then
                        rgb[#rgb+1] = number
                    end
                end
                if funcName == "fromRGB" then
                    for i, num in pairs(rgb) do
                        rgb[i] = num / 255
                    end
                elseif funcName == "fromHSV" then
                    if #rgb ~= 3 then
                        return
                    end
                    rgb = {hsvToRgb(rgb[1], rgb[2], rgb[3], 1)}
                end
                results[#results+1] = {
                    range = getRange(simple[1].start, simple[1].start + 1, lines),
                    color = {
                        red = rgb[1] or 0,
                        green = rgb[2] or 0,
                        blue = rgb[3] or 0,
                        alpha = 1
                    }
                }
            end
        end
    end)
    if #results == 0 then
        return nil
    end
    return results
end
