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

local function rgbToHsv(r, g, b, a)
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local h, s, v
    v = max

    local d = max - min
    if max == 0 then s = 0 else s = d / max end

    if max == min then
        h = 0 -- achromatic
    else
        if max == r then
        h = (g - b) / d
        if g < b then h = h + 6 end
        elseif max == g then h = (b - r) / d + 2
        elseif max == b then h = (r - g) / d + 4
        end
        h = h / 6
    end

    return h, s, v, a
end

--- @param lsp LSP
--- @param params table
--- @return table
return function (lsp, params)
    local vm, lines = lsp:getVM(params.textDocument.uri)
    if not vm then
        return
    end
    local result = nil
    vm:eachSource(function(source)
        if result then
            return
        end
        if source.type ~= "call" then
            return
        end
        local simple = source:get 'simple'
        if not simple then
            return
        end
        if #simple == 4 and simple[1][1] == "Color3" then
            local callArgs = simple[4]
            if
                table.equal(params.range, getRange(simple[1].start, simple[1].start + 1, lines))
                or table.equal(params.range, getRange(callArgs.start + 1, callArgs.finish - 1, lines))
            then
                local funcName = simple[3][1]
                if funcName == "new" then
                    for i, num in pairs(params.color) do
                        params.color[i] = tostring(num):sub(1, 8)
                    end
                elseif funcName == "fromRGB" then
                    for i, num in pairs(params.color) do
                        params.color[i] = tostring(math.floor(num * 255))
                    end
                elseif funcName == "fromHSV" then
                    local hsv = {rgbToHsv(params.color.red, params.color.green, params.color.blue, 1)}
                    hsv = {
                        red = hsv[1],
                        green = hsv[2],
                        blue = hsv[3]
                    }
                    for i in pairs(params.color) do
                        params.color[i] = tostring(hsv[i]):sub(1, 8)
                    end
                end
                local rgb = string.format("%s, %s, %s", params.color.red, params.color.green, params.color.blue)
                result = {
                    {
                        label = rgb,
                        textEdit = {
                            range = getRange(callArgs.start + 1, callArgs.finish - 1, lines),
                            newText = rgb
                        }
                    }
                }
            end
        end
    end)

    return result
end
