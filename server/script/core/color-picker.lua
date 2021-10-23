local files = require 'files'
local guide = require 'core.guide'
local brickcolors = require 'library.brickcolors'
local vm = require 'vm'

local COLOR3_CONSTRUCTORS = {
    ["Color3.new"] = true,
    ["Color3.fromRGB"] = true,
    ["Color3.fromHSV"] = true
}

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

local function hex2rgb(hex)
	hex = hex:gsub("#","")
	return tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
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

local function documentColor(uri)
    local ast = files.getAst(uri)
    if not ast then
        return
    end
    local results = {}
    guide.eachSourceType(ast.ast, "call", function(source)
        for _, def in ipairs(vm.getDefs(source.node)) do
            def = guide.getObjectValue(def) or def
            if def.special then
                if COLOR3_CONSTRUCTORS[def.special] then
                    local rgb = {}
                    if source.args then
                        for i, arg in ipairs(source.args) do
                            if arg.type == "number" then
                                rgb[i] = arg[1]
                            elseif vm.getInferType(arg) == "number" then
                                rgb[i] = vm.getInferLiteral(arg) or 0
                            else
                                return
                            end
                        end
                    end
                    if def.special == "Color3.fromRGB" then
                        for i, num in pairs(rgb) do
                            rgb[i] = num / 255
                        end
                    elseif def.special == "Color3.fromHSV" then
                        if #rgb ~= 3 then
                            return
                        end
                        rgb = {hsvToRgb(rgb[1], rgb[2], rgb[3], 1)}
                    end
                    results[#results+1] = {
                        range = files.range(uri, source.start, source.finish),
                        color = {
                            red = rgb[1] or 0,
                            green = rgb[2] or 0,
                            blue = rgb[3] or 0,
                            alpha = 1
                        }
                    }
                    break
                elseif def.special == "BrickColor.new" then
                    if source.args and #source.args == 1 and source.args[1].type == "string" then
                        local color = brickcolors[source.args[1][1]]
                        if color then
                            local r, g, b = color:match("(%d+), (%d+), (%d+)")
                            results[#results+1] = {
                                range = files.range(uri, source.start, source.finish),
                                color = {
                                    red = r / 255,
                                    green = g / 255,
                                    blue = b / 255,
                                    alpha = 1
                                }
                            }
                        end
                    end
                    break
                elseif def.special == "Color3.fromHex" then
                    if source.args and #source.args == 1 and source.args[1].type == "string" then
                        local hex = source.args[1][1]
                        local r, g, b = hex2rgb(hex)
                        if r and g and b then
                            results[#results+1] = {
                                range = files.range(uri, source.start, source.finish),
                                color = {
                                    red = r / 255,
                                    green = g / 255,
                                    blue = b / 255,
                                    alpha = 1
                                }
                            }
                        end
                    end
                    break
                end
            end
        end
    end)
    if #results == 0 then
        return nil
    end
    return results
end

local function colorPresentation(params)
    local uri = params.textDocument.uri
    local ast = files.getAst(uri)
    if not ast then
        return
    end
    local offsetStart, offsetFinish = files.unrange(uri, params.range)
    local func = nil
    local source = guide.eachSourceBetween(ast.ast, offsetStart, offsetFinish, function(source)
        if source.type == "call" then
            for _, def in ipairs(vm.getDefs(source.node)) do
                def = guide.getObjectValue(def) or def
                if def.special and COLOR3_CONSTRUCTORS[def.special] then
                    func = def
                    return source
                end
            end
        end
    end)
    if not source then
        return
    end
    local color = params.color
    if func.special == "Color3.new" then
        for i, num in pairs(color) do
            color[i] = tostring(num):sub(1, 8)
        end
    elseif func.special == "Color3.fromRGB" then
        for i, num in pairs(color) do
            color[i] = tostring(math.floor(num * 255))
        end
    elseif func.special == "Color3.fromHSV" then
        local hsv = {rgbToHsv(color.red, color.green, color.blue, 1)}
        hsv = {
            red = hsv[1],
            green = hsv[2],
            blue = hsv[3]
        }
        for i in pairs(color) do
            color[i] = tostring(hsv[i]):sub(1, 8)
        end
    end
    local rgb, start, finish
    if source.args then
        rgb = ("%s, %s, %s"):format(color.red, color.green, color.blue)
        start = source.args.start + 1
        finish = source.args.finish - 1
    else
        rgb = ("(%s, %s, %s)"):format(color.red, color.green, color.blue)
        start = source.node.finish + 1
        finish = source.finish
    end
    return {
        {
            label = rgb,
            textEdit = {
                range = files.range(uri, start, finish),
                newText = rgb
            }
        }
    }
end

return {
    documentColor = documentColor,
    colorPresentation = colorPresentation
}