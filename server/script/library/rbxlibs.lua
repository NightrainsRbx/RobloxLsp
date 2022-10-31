local json = require 'json'
local lang = require 'language'
local rojo = require 'library.rojo'
local util = require 'utility'
local defaultlibs

local m = {}

local MEMBER_SECURITY = {
    None = true,
    PluginSecurity = true,
    LocalUserSecurity = true,
}

local UNSCRIPTABLE_TAGS = {
    NotScriptable = true,
    -- Deprecated = true,
    Hidden = true,
}

local REPLICATE_TO_PLAYER = {
    StarterPack = "Backpack",
    StarterGui = "PlayerGui",
    StarterPlayerScripts = "PlayerScripts",
    StarterCharacterScripts = "Character"
}

local SPECIAL_FUNCTIONS = {
    ["ServiceProvider.GetService"] = "GetService",
    ["Instance.new"] = "Instance.new",
    ["Instance.FindFirstAncestorWhichIsA"] = "FindFirstClass",
    ["Instance.FindFirstChildWhichIsA"] = "FindFirstClass",
    ["Instance.FindFirstAncestorOfClass"] = "FindFirstClass",
    ["Instance.FindFirstChildOfClass"] = "FindFirstClass",
    ["Instance.FindFirstChild"] = "FindFirstChild",
    ["Instance.WaitForChild"] = "FindFirstChild",
    ["Instance.Clone"] = "Clone",
    ["Instance.IsA"] = "IsA",
    ["Color3.new"] = "Color3.new",
    ["Color3.fromRGB"] = "Color3.fromRGB",
    ["Color3.fromHSV"] = "Color3.fromHSV",
    ["Color3.fromHex"] = "Color3.fromHex",
    ["EnumItem.IsA"] = "EnumItem.IsA",
    ["BrickColor.new"] = "BrickColor.new"
}

m.RELEVANT_SERVICES = {
    ["BadgeService"] = "server",
    ["ChangeHistoryService"] = "server",
    ["CollectionService"] = "both",
    ["ContentProvider"] = "both",
    ["ContextActionService"] = "both",
    ["DataStoreService"] = "server",
    ["Debris"] = "both",
    ["GuiService"] = "client",
    ["HapticService"] = "client",
    ["HttpService"] = "both",
    ["Lighting"] = "both",
    ["LocalizationService"] = "both",
    ["MarketplaceService"] = "both",
    ["MessagingService"] = "server",
    ["PathfindingService"] = "both",
    ["PhysicsService"] = "both",
    ["Players"] = "both",
    ["PolicyService"] = "both",
    ["ProximityPromptService"] = "both",
    ["ReplicatedFirst"] = "both",
    ["ReplicatedStorage"] = "both",
    ["RunService"] = "both",
    ["ServerScriptService"] = "server",
    ["ServerStorage"] = "server",
    ["SocialService"] = "both",
    ["SoundService"] = "both",
    ["StarterGui"] = "both",
    ["StarterPack"] = "both",
    ["StarterPlayer"] = "both",
    ["Teams"] = "both",
    ["TeleportService"] = "both",
    ["TextService"] = "both",
    ["TweenService"] = "both",
    ["UserInputService"] = "client",
    ["VRService"] = "client",
    ["MemoryStoreService"] = "server",
    ["Workspace"] = "both",
}

m.instanceOrAnyIndex = {
    type = "type.index",
    instanceIndex = true,
    key = {
        [1] = "string",
        type = "type.name"
    },
    value = {
        type = "type.union",
        {
            [1] = "Instance",
            type = "type.name"
        },
        {
            [1] = "any",
            type = "type.name"
        }
    }
}

m.instanceIndex = {
    type = "type.index",
    instanceIndex = true,
    readOnly = true,
    key = {
        [1] = "string",
        type = "type.name"
    },
    value = {
        [1] = "Instance",
        type = "type.name"
    }
}

util.setTypeParent(m.instanceIndex.value, m.instanceIndex)

m.BrickColors = require 'library.brickcolors'

local function generateEnums(argName, enumType)
    local enums = {}
    local list = nil
    if enumType == 1 then
        list = m.ClassNames
    elseif enumType == 2 then
        list = m.Services
    elseif enumType == 3 then
        list = m.CreatableInstances
    elseif enumType == 4 then
        list = m.Enums
    elseif enumType == 5 then
        list = m.BrickColors
    else
        for _, enum in pairs(m.Api.Enums) do
            if enum.Name == enumType then
                for _, item in pairs(enum.Items) do
                    enums[#enums+1] =  {
                        argName = argName,
                        label = item.Name,
                        text = "Enum." .. enumType .. "." .. item.Name,
                        descLocation = {
                            parent = enumType,
                            enum = item.Name
                        },
                    }
                end
            end
        end
        return enums
    end
    for item, detail in pairs(list) do
        enums[#enums+1] = {
            argName = argName,
            label = '"' .. item .. '"',
            detail = type(detail) == "string" and detail or nil,
            descLocation = enumType < 4 and {
                class = item
            },
        }
    end
    return enums
end

local function getDocumentationLink(member, className)
    if m.ClassNames[className] then
        if member.MemberType == "Property" then
            return "https://developer.roblox.com/en-us/api-reference/property/" .. className .. "/" .. member.Name
        elseif member.MemberType == "Function" then
            return "https://developer.roblox.com/en-us/api-reference/function/" .. className .. "/" .. member.Name
        elseif member.MemberType == "Event" then
            return "https://developer.roblox.com/en-us/api-reference/event/" .. className .. "/" .. member.Name
        elseif member.MemberType == "Callback" then
            return "https://developer.roblox.com/en-us/api-reference/callback/" .. className .. "/" .. member.Name
        end
    else
        return "https://developer.roblox.com/en-us/api-reference/datatype/" .. className
    end
end

local function parseType(data, tbl)
    local name = data.Name
    if data.Category == "Enum" then
        name = "Enum." .. data.Name
    else
        if name == "void" then
            name = "nil"
        elseif name == "bool" then
            name = "boolean"
        elseif name == "int" or name == "double" or name == "float" or name == "int64" then
            name = "number"
        elseif name == "Variant" then
            name = "any"
        elseif name == "Content" then
            name = "string"
        elseif name == "Function" then
            name = "function"
        end
    end
    if name == "Tuple" then
        return {
            type = "type.variadic",
            value = {
                type = "type.name",
                [1] = "any",
            }
        }
    elseif name == "Array" then
        return {
            type = "type.table",
            {
                type = "type.name",
                [1] = data.Generic or "any"
            }
        }
    elseif name == "Objects" then
        return {
            type = "type.table",
            {
                type = "type.name",
                [1] = data.Generic or "Instance"
            }
        }
    elseif name == "Dictionary" then
        return {
            type = "type.table",
            {
                type = "type.index",
                key = {
                    type = "type.name",
                    [1] = "string"
                },
                value = {
                    type = "type.name",
                    [1] = data.Generic or "any"
                }
            }
        }
    else
        local tp = tbl or {}
        tp.type = "type.name"
        tp[1] = name
        return tp
    end
end

local function parseParameters(data)
    local params = {
        type = "type.list",
        funcargs = true,
    }
    for _, param in ipairs(data) do
        if param.Type.Name == "Tuple" then
            params[#params+1] = {
                type = "type.variadic",
                value = {
                    [1] = "any",
                    type = "type.name"
                }
            }
        else
            params[#params+1] = parseType(param.Type, {
                paramName = {param.Name},
                default = (param.Default and param.Default ~= "nil") and param.Default or nil,
                optional = param.Default and true or nil,
            })
        end
    end
    return params
end

local function parseMembers(data, isObject)
    local members = {}
    local overload = {}
    for _, member in ipairs(data.Members) do
        local fullName = data.Name .. "." .. member.Name
        local hidden = nil
        local deprecated = nil
        local readOnly = nil
        local description = ""
        if member.Deprecated then
            deprecated = true
        end
        if member.Tags then
            local tags = {}
            for _, tag in pairs(member.Tags) do
                if tag == "Deprecated" then
                    deprecated = true
                elseif tag == "Hidden" then
                    hidden = true
                elseif tag == "ReadOnly" then
                    readOnly = true
                elseif tag == "NotScriptable" then
                    goto CONTINUE
                end
                tags[#tags+1] = tag
            end
            if #tags > 0 then
                description = ("%s\n\n*tags: %s.*"):format(description, table.concat(tags, ", "))
            end
        end
        if member.Security then
            local security = type(member.Security) == "string" and member.Security or member.Security.Read
            if not MEMBER_SECURITY[security] then
                goto CONTINUE
            end
            if security ~= "None" then
                description = ("%s\n\n*security: %s.*"):format(description, security)
            end
        end
        if deprecated and (member.Name:sub(1, 1) == member.Name:sub(1, 1):lower() or data.Name == "Vector3") then
            hidden = true
        end
        local docLink = getDocumentationLink(member, data.Name)
        if docLink then
            description = ("%s\n\n[%s](%s)"):format(description, lang.script.HOVER_VIEW_DOCUMENTS, docLink)
        end
        if member.MemberType == "Property" then
            local enums = nil
            if member.ValueType.Category == "Enum" then
                enums = generateEnums(nil, member.ValueType.Name)
            end
            members[#members+1] = {
                name = member.Name,
                type = "type.library",
                kind = "property",
                description = description,
                value = parseType(member.ValueType, {
                    enums = enums
                }),
                hidden = hidden,
                deprecated = deprecated,
                readOnly = readOnly
            }
            util.setTypeParent(members[#members])
            if member.Name == "Parent" and data.Name == "Instance" then
                m.instanceParent = members[#members].value
            end
        elseif member.MemberType == "Function" or member.MemberType == "Callback" then
            local returns
            if member.TupleReturns then
                returns = {
                    type = "type.list"
                }
                for _, rtn in ipairs(member.TupleReturns) do
                    returns[#returns+1] = parseType(rtn)
                end
            elseif member.ReturnType then
                returns = parseType(member.ReturnType)
            end
            local enums = m.FunctionEnums[fullName]
            if not enums then
                for _, param in pairs(member.Parameters) do
                    if param.Type.Category == "Enum" then
                        enums = enums or {}
                        util.mergeTable(enums, generateEnums(param.Name, param.Type.Name))
                    end
                end
            end
            local child = {
                name = member.Name,
                type = "type.library",
                description = description,
                method = isObject and member.MemberType ~= "Callback" or nil,
                value = {
                    type = "type.function",
                    args = parseParameters(member.Parameters),
                    returns = returns,
                    special = SPECIAL_FUNCTIONS[fullName],
                    enums = enums
                },
                hidden = hidden,
                deprecated = deprecated,
                readOnly = member.MemberType ~= "Callback",
            }
            if isObject and member.MemberType ~= "Callback" then
                table.insert(child.value.args, 1, {
                    [1] = data.Name,
                    type = "type.name",
                    paramName = {"self"}
                })
            end
            util.setTypeParent(child)
            if overload[member.Name] then
                local other = members[overload[member.Name]]
                if other.value.type ~= "type.inter" then
                    other.value = {
                        type = "type.inter",
                        special = SPECIAL_FUNCTIONS[fullName],
                        returns = other.value.returns,
                        [1] = other.value
                    }
                end
                other.value[#other.value+1] = child.value
                util.setTypeParent(other)
            else
                members[#members+1] = child
                overload[member.Name] = #members
            end
        elseif member.MemberType == "Event" then
            local params = member.Parameters and parseParameters(member.Parameters)
            local paramsLabel = nil
            local child = {}
            if params and #params > 0 then
                local paramsStr = require("core.guide").buildTypeAnn(params)
                paramsLabel = string.format("\n%s  -> %s\n", INV .. INV, paramsStr)
                child[1] = {
                    name = "Wait",
                    type = "type.library",
                    method = true,
                    value = {
                        type = "type.function",
                        args = {
                            type = "type.list",
                            funcargs = true,
                            {
                                [1] = "RBXScriptSignal",
                                type = "type.name",
                                paramName = {"self"}
                            }
                        },
                        returns = #params == 1 and params[1] or params
                    }
                }
                for _, key in ipairs({"Connect", "ConnectParallel", "Once"}) do
                    child[#child+1] = {
                        name = key,
                        type = "type.library",
                        method = true,
                        value = {
                            type = "type.function",
                            args = {
                                type = "type.list",
                                funcargs = true,
                                {
                                    [1] = "RBXScriptSignal",
                                    type = "type.name",
                                    paramName = {"self"}
                                },
                                {
                                    paramName = {"callback"},
                                    type = "type.function",
                                    args = params,
                                    returns = {
                                        type = "type.list"
                                    }
                                }
                            },
                            returns = {
                                [1] = "RBXScriptConnection",
                                type = "type.name"
                            }
                        }
                    }
                end
            end
            members[#members+1] = {
                name = member.Name,
                type = "type.library",
                kind = "event",
                extra = paramsLabel,
                description = description,
                value = {
                    type = "type.name",
                    [1] = "RBXScriptSignal",
                    parentClass = data.Name,
                    params = params,
                    child = child
                },
                hidden = hidden,
                deprecated = deprecated,
                readOnly = true
            }
            util.setTypeParent(members[#members])
        end
        ::CONTINUE::
    end
    return members
end

local function parseEnums()


    local typeofEnums = {}
    for tp in pairs(m.object) do
        if tp == "Instance" or not m.ClassNames[tp] and tp ~= "any" then
            typeofEnums[#typeofEnums+1] = {
                text = "\"" .. tp .. "\"",
                label = "\"" .. tp .. "\""
            }
        end
    end
    m.global["typeof"].value.enums = typeofEnums

    local enums = m.object["Enums"]
    for _, enum in pairs(m.Api.Enums) do
        local items = {
            {
                name = "GetEnumItems",
                type = "type.library",
                value = {
                    type = "type.function",
                    args = {
                        type = "type.list",
                        funcargs = true,
                        {
                            [1] = "Enum",
                            type = "type.name",
                            paramName = {"self"}
                        }
                    },
                    returns = {
                        type = "type.table",
                        {
                            type = "type.name",
                            [1] = "Enum." .. enum.Name
                        }
                    }
                }
            }
        }
        local child = {
            name = enum.Name,
            type = "type.library",
            kind = "field",
            value = {
                [1] = "Enum",
                type = "type.name",
                child = items
            }
        }
        for _, item in pairs(enum.Items) do
            items[#items+1] = {
                name = item.Name,
                type = "type.library",
                kind = "field",
                value = {
                    [1] = "Enum." .. enum.Name,
                    type = "type.name"
                }
            }
            m.object["Enum." .. enum.Name] = {
                ref = {
                    {
                        name = "EnumType",
                        type = "type.library",
                        value = child.value
                    }
                },
                child = m.object["EnumItem"].child
            }
        end
        util.setTypeParent(child)
        enums.child[#enums.child+1] = child
    end
end

local function addSuperMembers(class, superClass, mark)
    if not m.object[superClass] then
        return
    end
    if not mark then
        mark = {}
        for _, child in ipairs(m.object[class].child) do
            mark[child.name] = true
        end
    end
    for _, child in ipairs(m.object[superClass].child) do
        if not mark[child.name] then
            mark[child.name] = true
            table.insert(m.object[class].child, child)
        end
    end
    addSuperMembers(class, m.ClassNames[superClass], mark)
end

function m.getClassNames()
    if not m.ClassNames then
        m.ClassNames = {}
        m.Services = {
            ["UserGameSettings"] = true,
            ["DebugSettings"] = true,
            ["LuaSettings"] = true,
            ["PhysicsSettings"] = true
        }
        m.CreatableInstances = {}
        m.Enums = {}
        local api = m.loadApi()
        for _, rbxClass in pairs(api.Classes) do
            local notCreatable = false
            if rbxClass.Tags then
                for _, tag in pairs(rbxClass.Tags) do
                    if UNSCRIPTABLE_TAGS[tag] then
                        goto CONTINUE
                    end
                    if tag == "Service" then
                        m.Services[rbxClass.Name] = true
                    end
                    if tag == "NotCreatable" then
                        notCreatable = true
                    end
                end
            end
            if not notCreatable then
                m.CreatableInstances[rbxClass.Name] = true
            end
            m.ClassNames[rbxClass.Name] = rbxClass.Superclass
            ::CONTINUE::
        end
        for _, enum in pairs(api.Enums) do
            m.Enums[enum.Name] = true
        end
    end
    return m.ClassNames
end

function m.isA(class, super)
    if not class then
        return
    end
    if class == super then
        return true
    elseif m.ClassNames[class] then
        if m.ClassNames[class] == super then
            return true
        else
            return m.isA(m.ClassNames[class], super)
        end
    end
    return false
end

local function applyCorrections(api)
    local corrections = json.decode(util.loadFile(ROOT / "api" / "Corrections.json"))
    for _, class in ipairs(corrections.Classes) do
        for _, otherClass in ipairs(api.Classes) do
            if otherClass.Name == class.Name then
                for _, member in ipairs(class.Members) do
                    for _, otherMember in ipairs(otherClass.Members) do
                        if otherMember.Name == member.Name then
                            if member.TupleReturns then
                                otherMember.ReturnType = nil
                                otherMember.TupleReturns = member.TupleReturns
                            elseif member.ReturnType then
                                otherMember.ReturnType.Name = member.ReturnType.Name or otherMember.ReturnType.Name
                                otherMember.ReturnType.Generic = member.ReturnType.Generic
                            elseif member.ValueType then
                                otherMember.ValueType.Name = member.ValueType.Name or otherMember.ValueType.Name
                                otherMember.ValueType.Generic = member.ValueType.Generic
                            end
                            if member.Parameters then
                                for _, param in pairs(member.Parameters) do
                                    for _, otherParam in pairs(otherMember.Parameters) do
                                        if otherParam.Name == param.Name then
                                            if param.Type then
                                                otherParam.Type.Name = param.Type.Name or otherParam.Type.Name
                                                otherParam.Type.Generic = param.Type.Generic
                                            end
                                            if param.Default then
                                                otherParam.Default = param.Default
                                            end
                                        end
                                    end
                                end
                            end
                            break
                        end
                    end
                end
                break
            end
        end
    end
end

function m.loadApi()
    if not m.Api then
        local apiDump = json.decode(util.loadFile(ROOT / "api" / "API-Dump.json"))
        local dataTypes = json.decode(util.loadFile(ROOT / "api" / "DataTypes.json"))
        applyCorrections(apiDump)
        for key, value in pairs(dataTypes) do
            apiDump[key] = value
        end
        m.Api = apiDump
    end
    return m.Api
end

local function htmlReplace(tag, attrs, content)
    content = content or ""
    if tag == "code" then
        if attrs and attrs:match("class=\"language%-lua\"") then
            content = content:gsub("&quot;", "\""):gsub("\n\n", "\n")
            return "```lua\n" .. content .. "\n```"
        end
        local title = content:match("|(.-)$")
        if title then
            content = content:match("^(.-)|")
        end
        if content:lower():match("^articles[%./]") then
            content = content:match("[%./](.-)$")
            return ("[%s](https://developer.roblox.com/en-us/articles/%s)"):format(title or content, content:gsub("%s", "-"))
        elseif content:lower():match("^datatype[%./]") then
            content = content:match("[%./](.-)$")
            return ("[%s](https://developer.roblox.com/en-us/api-reference/datatype/%s)"):format(title or content, content)
        elseif content:lower():match("^enum[%./]") then
            content = content:match("[%./](.-)$")
            return ("[%s](https://developer.roblox.com/en-us/api-reference/enum/%s)"):format(title or content, content)
        elseif content:match("^(.+)[%./:](.+)$") then
            local class, member = content:match("^(.+)[%./:](.+)$")
            local object = m.object[class]
            if object then
                for _, child in ipairs(object.child) do
                    if child.name == member then
                        if child.value.type == "type.function" then
                            return ("[%s](https://developer.roblox.com/en-us/api-reference/function/%s/%s)"):format(title or content, class, member)
                        elseif child.kind == "property" then
                            return ("[%s](https://developer.roblox.com/en-us/api-reference/property/%s/%s)"):format(title or content, class, member)
                        elseif child.kind == "event" then
                            return ("[%s](https://developer.roblox.com/en-us/api-reference/event/%s/%s)"):format(title or content, class, member)
                        end
                        break
                    end
                end
            end
        elseif m.object[content] then
            return ("[%s](https://developer.roblox.com/en-us/api-reference/class/%s)"):format(title or content, content)
        end
        return "`" .. (title or content) .. "`"
    elseif tag == "em" or tag == "i" then
        return "*" .. content .. "*"
    elseif tag == "strong" or tag == "b" then
        return "**" .. content .. "**"
    elseif tag == "h2" then
        return "## " .. content
    elseif tag == "li" then
        return "* " .. content
    elseif tag == "a" and attrs then
        local href = attrs:match("href=\"(.-)\"")
        if href then
            if href:sub(1, 4) ~= "http" then
                href = "https://developer.roblox.com/" .. href
            end
            local title = attrs:match("title=\"(.-)\"") or content
            return ("[%s](%s)"):format(title, href)
        end
    elseif tag == "img" and attrs then
        local src = attrs:match("src=\"(.-)\"")
        if src then
            if src:sub(1, 4) ~= "http" then
                src = "https://developer.roblox.com/" .. src
            end
            local alt = attrs:match("alt=\"(.-)\"")
            return ("![%s](%s \"%s\")"):format(alt or content, src, content)
        end
    end
    return content
end

local function parseHtmlToMarkdown(str)
    str = str:gsub("\n", "\n\n"):gsub("></", "> </")
    repeat
        local c = 0
        str, c = str:gsub("<(%w+)([^>]*)>(.-)</%1>", htmlReplace)
    until c == 0
    str = str:gsub("<(%w+)([^>]*)>", htmlReplace)
    return str
end

local function parseDocumentaion()
    if not m.Docs then
        m.Docs = json.decode(util.loadFile(ROOT / "api" / "API-Docs.json"))
    end
    local success, err = pcall(function ()
        for id, doc in pairs(m.Docs) do
            doc = type(doc) == "table" and doc.documentation or doc
            if type(doc) ~= "string" or #doc == 0 or doc == "<p>TBD</p>" then
                goto CONTINUE
            end
            id = util.split(id, "/")
            local object = nil
            for i = 2, #id do
                if i == 2 then
                    if id[i] == "global" then
                        object = m.global
                    elseif id[i] == "globaltype" then
                        object = m.object
                    elseif id[i] == "enum" then
                        object = m.object
                        id[3] = "Enums." .. id[3]
                    end
                elseif i == 3 then
                    local names = util.split(id[i], "%.")
                    if names[2] == "FromNormalId" or names[2] == "FromAxis" then
                        names[2] = "f" .. names[2]:sub(2)
                    end
                    object = object[names[1]]
                    if object then
                        for j = 2, #names do
                            local fields = object.child or object.value
                            object = nil
                            if fields then
                                fields = fields.child or fields
                                for key, field in ipairs(fields) do
                                    if (key == names[j])
                                    or (field.type == "type.field" and field.key[1] == names[j])
                                    or (field.type == "type.library" and field.name == names[j]) then
                                        object = field
                                        break
                                    end
                                end
                            end
                            if not object then
                                break
                            end
                        end
                    end
                elseif id[i] == "overload" then
                    if object.value.type == "type.inter" then
                        local guide = require("core.guide")
                        local tp = id[i + 1]
                            :gsub("[%?%s]", "")
                            :gsub("Tuple", "...any")
                        for index, value in ipairs(object.value) do
                            value = guide.getObjectValue(value) or value
                            local tp2 = guide.buildTypeAnn(value)
                                :gsub("%w+: ", "")
                                :gsub("[%?%s]", "")
                                :gsub("Array<.->", "table")
                            if tp == tp2 then
                                if i + 1 == #id then
                                    if not object.overloadDescription then
                                        object.overloadDescription = {}
                                    end
                                    object.overloadDescription[index] = {}
                                    object = object.overloadDescription[index]
                                else
                                    object = value
                                end
                                goto NEXT
                            end
                        end
                        object = nil
                        ::NEXT::
                    end
                elseif id[i] == "param" then
                    local args = object.args or (object.value and object.value.args)
                    if args then
                        object = args[tonumber(id[i + 1]) + 1]
                    else
                        object = nil
                    end
                elseif id[i] == "return" then
                    local returns = object.returns or (object.value and object.value.returns)
                    if returns then
                        if returns.type == "type.list" then
                            object = returns[tonumber(id[i + 1]) + 1]
                        else
                            object = returns
                        end
                    else
                        object = nil
                    end
                end
                if object == nil then
                    break
                end
            end
            if type(object) == "table" then
                object.description = parseHtmlToMarkdown(doc) .. (object.description or "")
            end
            ::CONTINUE::
        end
        m.object.string.child = {}
        for _, field in ipairs(m.global.string.value) do
            field = util.shallowCopy(field)
            field.type = "type.library"
            field.value = util.deepCopy(field.value)
            field.method = true
            field.name = field.key[1]
            util.setTypeParent(field)
            m.object.string.child[#m.object.string.child+1] = field
        end
    end)
    if not success then
        log.error(err)
    end
end

local function setChildParent(obj, parent)
    if obj.kind ~= "child" then
        return
    end
    if obj.value.child then
        for _, nextChild in pairs(obj.value.child) do
            setChildParent(nextChild, obj.value)
        end
    else
        obj.value.child = {}
    end
    local value = util.shallowCopy(parent)
    value.override = m.instanceParent
    obj.value.child["Parent"] = {
        name = "Parent",
        type = "type.library",
        kind = "property",
        value = value
    }
end

local function replicateToPlayer(dataModelChild)
    local playerChild = util.deepCopy(defaultlibs.playerChild)
    util.setTypeParent(playerChild)
    for _, child in pairs(dataModelChild) do
        if REPLICATE_TO_PLAYER[child.name] then
            util.joinTable(playerChild[REPLICATE_TO_PLAYER[child.name]].value.child, child.value.child)
        end
        if child.name == "StarterPlayer" then
            for _, child in pairs(child.value.child) do
                if REPLICATE_TO_PLAYER[child.name] then
                    util.joinTable(playerChild[REPLICATE_TO_PLAYER[child.name]].value.child, child.value.child)
                end
            end
        end
    end
    m.object["Player"].ref = playerChild
    for _, child in ipairs(m.object["Player"].child) do
        if child.name == "CharacterAdded" then
            child.value.params[1].child = playerChild["Character"].value.child
            break
        end
    end
end

local function buildDataModel()
    local game = m.global["game"]
    local dataModelChild = util.deepCopy(defaultlibs.dataModelChild)
    game.value.child = dataModelChild
    util.setTypeParent(game)
    for _, child in pairs(dataModelChild) do
        setChildParent(child, game.value)
    end
    local datamodel = rojo:parseDatamodel()
    if datamodel then
        util.mergeTable(game.value.child, datamodel)
        for _, child in pairs(datamodel) do
            setChildParent(child, game.value)
        end
    end
    local rojoProject = rojo:loadRojoProject()
    if rojoProject then
        if rojoProject.value[1] == "DataModel" then
            util.mergeTable(game, rojoProject)
            for _, child in pairs(rojoProject.value.child) do
                setChildParent(child, game.value)
            end
        else
            for _, child in pairs(rojoProject.value.child) do
                setChildParent(child, rojoProject.value)
            end
        end
    end
    for _, child in pairs(game.value.child) do
        if m.Services[child.value[1]] then
            m.object[child.value[1]].ref = child.value.child
        end
    end
    replicateToPlayer(game.value.child)
end

local function parseClasses(api)
    local classNames = m.getClassNames()
    m.FunctionEnums = {
        ["ServiceProvider.GetService"] = generateEnums("className", 2),
        ["Instance.new"] = generateEnums("className", 3),
        ["Instance.IsA"] = generateEnums("className", 1),
        ["Instance.FindFirstAncestorWhichIsA"] = generateEnums("className", 1),
        ["Instance.FindFirstChildWhichIsA"] = generateEnums("className", 1),
        ["Instance.FindFirstAncestorOfClass"] = generateEnums("className", 1),
        ["Instance.FindFirstChildOfClass"] = generateEnums("className", 1),
        ["EnumItem.IsA"] = generateEnums("enumName", 4),
        ["BrickColor.new"] = generateEnums("val", 5)
    }
    for _, class in ipairs(api.Classes) do
        if classNames[class.Name] then
            m.object[class.Name] = {
                child = parseMembers(class, true)
            }
        end
    end
    for class, superClass in pairs(classNames) do
        if m.object[class] then
            addSuperMembers(class, superClass)
        end
    end
end

local function parseDataTypes(api)
    for _, dataType in ipairs(api.DataTypes) do
        m.object[dataType.Name] = {
            child = parseMembers(dataType, true)
        }
    end
    for _, constructor in ipairs(api.Constructors) do
        local value = {
            type = "type.table"
        }
        for _, member in ipairs(parseMembers(constructor)) do
            member.type = "type.field"
            member.key = {member.name}
            member.name = nil
            value[#value+1] = member
        end
        m.global[constructor.Name] = {
            name = constructor.Name,
            kind = "global",
            type = "type.library",
            value = value
        }
        util.setTypeParent(m.global[constructor.Name])
    end
end

local function loadMeta()
    local state = require("parser"):compile(util.loadFile(ROOT / "def" / "meta.luau"), "lua")
    if state then
        for _, object in ipairs(state.ast.types[1].value) do
            m.object[object.key[1]].meta = {
                type = "metatable",
                value = object.value
            }
        end
    end
end

function m.init()
    defaultlibs = require("library.defaultlibs")
    defaultlibs.init()

    m.global = util.deepCopy(defaultlibs.global)
    m.object = util.deepCopy(defaultlibs.object)

    local api = m.loadApi()
    parseClasses(api)
    parseDataTypes(api)
    loadMeta()
    parseEnums()
    parseDocumentaion()
    buildDataModel()

    require("vm").flushCache()
end

return m