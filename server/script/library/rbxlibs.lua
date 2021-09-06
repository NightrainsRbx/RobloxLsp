local json = require 'json'
local lang = require 'language'
local rojo = require 'library.rojo'
local util = require 'utility'
local xml = require 'xml'

local defaultlibs

local m = {}

m.BrickColors = require 'library.brickcolors'

local MEMBER_SECURITY = {
    None = true,
    PluginSecurity = true
}

local UNSCRIPTABLE_TAGS = {
    NotScriptable = true,
    Deprecated = true,
    Hidden = true,
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
    ["EnumItem.IsA"] = "EnumItem.IsA",
    ["BrickColor.new"] = "BrickColor.new"
}

m.RELEVANT_SERVICES = {
    ["BadgeService"] = 1,
    ["ChangeHistoryService"] = 1,
    ["CollectionService"] = 0,
    ["ContentProvider"] = 0,
    ["ContextActionService"] = 0,
    ["DataStoreService"] = 1,
    ["Debris"] = 0,
    ["GuiService"] = 2,
    ["HapticService"] = 2,
    ["HttpService"] = 0,
    ["Lighting"] = 0,
    ["LocalizationService"] = 0,
    ["MarketplaceService"] = 0,
    ["MessagingService"] = 1,
    ["PathfindingService"] = 0,
    ["PhysicsService"] = 0,
    ["Players"] = 0,
    ["PolicyService"] = 0,
    ["ProximityPromptService"] = 0,
    ["ReplicatedFirst"] = 0,
    ["ReplicatedStorage"] = 0,
    ["RunService"] = 0,
    ["ServerScriptService"] = 1,
    ["ServerStorage"] = 1,
    ["SocialService"] = 0,
    ["SoundService"] = 0,
    ["StarterGui"] = 0,
    ["StarterPack"] = 0,
    ["StarterPlayer"] = 0,
    ["Stats"] = 0,
    ["Teams"] = 0,
    ["TeleportService"] = 0,
    ["TextService"] = 0,
    ["TweenService"] = 0,
    ["UserInputService"] = 2,
    ["VRService"] = 2,
}

local REPLICATE_TO_PLAYER = {
    StarterPack = "Backpack",
    StarterGui = "PlayerGui",
    StarterPlayerScripts = "PlayerScripts",
    StarterCharacterScripts = "Character"
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
                        text = "Enum." .. enumType .. "." .. item.Name
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
            description = m.ClassDocs[item] and m.ClassDocs[item].__Summary
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
    end
    local tp = tbl or {}
    tp.type = "type.name"
    tp[1] = name
    local generic = data.Generic
    if name == "Objects" then
        tp[1] = "Array"
        tp.typeAlias = defaultlibs.customType.Array
        generic = generic or "Instance"
    elseif name == "Array" then
        tp.typeAlias = defaultlibs.customType.Array
        generic = generic or "any"
    elseif name == "Dictionary" then
        tp.typeAlias = defaultlibs.customType.Dictionary
        generic = generic or "any"
    end
    if generic then
        tp.generics = {
            type = "type.generics",
            {
                type = "type.name",
                [1] = generic
            }
        }
    end
    return tp
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
        if member.Security then
            if type(member.Security) == "string" and not MEMBER_SECURITY[member.Security] then
                goto CONTINUE
            elseif type(member.Security) == "table" then
                if not MEMBER_SECURITY[member.Security.Read] then
                    goto CONTINUE
                end
            end
        end
        local fullName = data.Name .. "." .. member.Name
        local hidden = nil
        local deprecated = nil
        local readOnly = nil
        local description = ""
        local overloadDescription = nil
        if m.ClassDocs[data.Name] then
            if type(m.ClassDocs[data.Name][member.Name]) == "string" then
                description = m.ClassDocs[data.Name][member.Name]
            else
                overloadDescription = m.ClassDocs[data.Name][member.Name]
            end
        else
            for class, _docs in pairs(m.ClassDocs) do
                if m.isA(class, data.Name) then
                    if _docs[member.Name] then
                        description = _docs[member.Name]
                    end
                end
            end
        end
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
                description = string.format("%s\n\n*tags: %s.*", description, table.concat(tags, ", "))
            end
        end
        if deprecated and (member.Name:sub(1, 1) == member.Name:sub(1, 1):lower() or data.Name == "Vector3") then
            hidden = true
        end
        local docs = getDocumentationLink(member, data.Name)
        if docs then
            description = ("%s\n\n[%s](%s)"):format(description, lang.script.HOVER_VIEW_DOCUMENTS, docs)
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
                overloadDescription = overloadDescription,
                value = {
                    type = "type.function",
                    args = parseParameters(member.Parameters),
                    returns = returns,
                    method = isObject and member.MemberType ~= "Callback" or nil,
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
                paramsLabel = string.format("\n\f\f  -> %s\n", paramsStr)
                child[1] = {
                    name = "Wait",
                    type = "type.library",
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
                        returns = #params == 1 and params[1] or params,
                        method = true
                    }
                }
                for _, key in ipairs({"Connect", "ConnectParallel"}) do
                    child[#child+1] = {
                        name = key,
                        type = "type.library",
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
                            },
                            method = true
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
                        [1] = "Array",
                        type = "type.name",
                        typeAlias = defaultlibs.customType.Array,
                        generics = {
                            type = "type.generics",
                            {
                                [1] = "Enum." .. enum.Name,
                                type = "type.name"
                            }
                        }
                    },
                    method = true
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

local function parseReflectionMetadata()
    local htmlToMarkdown = json.decode(util.loadFile(ROOT / "rbx" / "html_md.json"))
    local data = xml.parser.parse(util.loadFile(ROOT / "rbx" / "ReflectionMetadata.xml"))
    local classes = xml.getAttr(data.children[1], "class", "ReflectionMetadataClasses")
    xml.forAttr(classes, "class", "ReflectionMetadataClass", function(class)
        local properties = xml.getTag(class, "Properties")
        local className = xml.getChild(xml.getAttr(properties, "name", "Name"), "text")
        local summary = xml.getChild(xml.getAttr(properties, "name", "summary"), "text")
        local docs = m.ClassDocs[className] or {}
        if summary and summary:match("%&%w+") then
            summary = htmlToMarkdown[className]
        end
        docs.__Summary = summary
        xml.forTag(class, "Item", function(item)
            xml.forAttr(item, "class", "ReflectionMetadataMember", function(member)
                local properties = xml.getTag(member, "Properties")
                if properties then
                    local memberName = xml.getChild(xml.getAttr(properties, "name", "Name"), "text")
                    local summary = xml.getChild(xml.getAttr(properties, "name", "summary"), "text")
                    if summary and summary:match("%&%w+") then
                        summary = htmlToMarkdown[memberName]
                    end
                    docs[memberName] = summary
                end
            end)
        end)
        m.ClassDocs[className] = docs
    end)
end

local function parseAutocompleteMetadata()
    local data = xml.parser.parse(util.loadFile(ROOT / "rbx" / "AutocompleteMetadata.xml"))
    local items = xml.getTag(data, "StudioAutocomplete")
    xml.forTag(items, "ItemStruct", function(struct)
        local className = struct.attrs.name
        if className == "EventInstance" then
            className = "RBXScriptSignal"
        elseif className == "RobloxScriptConnection" then
            className = "RBXScriptConnection"
        end
        local docs = m.ClassDocs[className] or {}
        local overload = {}
        xml.forTag(struct, "Function", function(func)
            local memberName = func.attrs.name
            local description = xml.getChild(xml.getTag(func, "description"), "text")
            if description then
                if className ~= "Color3" and overload[memberName] then
                    if type(docs[memberName]) == "string" then
                        docs[memberName] = {
                            docs[memberName]
                        }
                    end
                    table.insert(docs[memberName], description)
                else
                    docs[memberName] = description
                end
            end
            overload[memberName] = true
        end)
        xml.forTag(struct, "Properties", function(properties)
            for _, prop in pairs(properties.children) do
                if not prop.attrs then
                    return
                end
                local memberName = prop.attrs.name
                local description = xml.getChild(prop, "text")
                if description then
                    docs[memberName] = description
                end
            end
        end)
        m.ClassDocs[className] = docs
    end)
end

local function addSuperMembers(class, superClass, mark)
    if not m.object[superClass] then
        return
    end
    mark = mark or {}
    for _, child in ipairs(m.object[superClass].child) do
        if not mark[child] then
            mark[child] = true
            table.insert(m.object[class].child, child)
        end
    end
    addSuperMembers(class, m.ClassNames[superClass], mark)
end

function m.getClassNames()
    if not m.ClassNames then
        m.ClassNames = {}
        m.Services = {
            ["UserGameSettings"] = true
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
    local corrections = json.decode(util.loadFile(ROOT / "rbx" / "Corrections.json"))
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
        local apiDump = json.decode(util.loadFile(ROOT / "rbx" / "API-Dump.json"))
        local dataTypes = json.decode(util.loadFile(ROOT / "rbx" / "datatypes.json")
                                   or util.loadFile(ROOT / "rbx" / "DataTypes.json"))
        applyCorrections(apiDump)
        for key, value in pairs(dataTypes) do
            apiDump[key] = value
        end
        m.Api = apiDump
        m.ClassDocs = {}
        parseReflectionMetadata()
        parseAutocompleteMetadata()
    end
    return m.Api
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
    local datamodel = rojo.DataModel
    if datamodel then
        util.mergeTable(game.value.child, datamodel)
        for _, child in pairs(datamodel) do
            setChildParent(child, game.value)
        end
    end
    local rojoProject = rojo:loadRojoProject()
    if rojoProject then
        util.mergeTable(game, rojoProject)
        for _, child in pairs(rojoProject.value.child) do
            setChildParent(child, game.value)
        end
    end
    for _, child in pairs(game.value.child) do
        if m.object[child.value[1]] then
            m.object[child.value[1]].ref = child.value.child
        end
    end
    replicateToPlayer(game.value.child)
end

local function loadMeta()
    local parser = require("parser")
    local state = parser:compile(util.loadFile(ROOT / "def" / "meta.luau"), "lua")
    for _, object in ipairs(state.ast.types[1].value) do
        local meta = {}
        for _, field in ipairs(object.value) do
            meta[#meta+1] = {
                type = "type.meta",
                method = field.key[1],
                value = field.value
            }
        end
        m.object[object.key[1]].meta = meta
    end
end

function m.init()
    defaultlibs = defaultlibs or require("library.defaultlibs")
    if not defaultlibs.initialized then
        defaultlibs.init()
    end
    m.global = util.deepCopy(defaultlibs.global)
    m.object = util.deepCopy(defaultlibs.object)
    local api = m.loadApi()
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
    buildDataModel()
    for class, superClass in pairs(classNames) do
        if m.object[class] then
            addSuperMembers(class, superClass)
        end
    end
    for _, dataType in ipairs(api.DataTypes) do
        m.object[dataType.Name] = {
            child = parseMembers(dataType, true)
        }
    end
    loadMeta()
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
    parseEnums()
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
    require("vm").flushCache()
end

return m