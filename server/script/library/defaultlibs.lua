local lang    = require 'language'
local util    = require 'utility'
local fs      = require 'bee.filesystem'

local m = {}

m.namespace = {
    Enum = true,
    Roact = true,
    Rodux = true
}

m.primitiveTypes = {
    ["string"] = true,
    ["table"] = true,
    ["boolean"] = true,
    ["number"] = true,
    ["thread"] = true,
    ["any"] = true,
    ["nil"] = true,
    ["function"] = true,
    ["symbol"] = true
}

m.dataModelChild = {
	Players = {
		name = "Players",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "Players",
            type = "type.name"
		}
	},
	Lighting = {
		name = "Lighting",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "Lighting",
            type = "type.name"
		}
	},
	ServerStorage = {
		name = "ServerStorage",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "ServerStorage",
            type = "type.name"
		}
	},
	ServerScriptService = {
		name = "ServerScriptService",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "ServerScriptService",
            type = "type.name"
		}
	},
	ReplicatedStorage = {
		name = "ReplicatedStorage",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "ReplicatedStorage",
            type = "type.name"
		}
	},
	ReplicatedFirst = {
		name = "ReplicatedFirst",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "ReplicatedFirst",
            type = "type.name"
		}
	},
	StarterGui = {
		name = "StarterGui",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "StarterGui",
            type = "type.name"
		}
	},
	StarterPack = {
		name = "StarterPack",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "StarterPack",
            type = "type.name"
		}
	},
	SoundService = {
		name = "SoundService",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "SoundService",
            type = "type.name"
		}
	},
	Workspace = {
		name = "Workspace",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "Workspace",
            type = "type.name"
		}
	},
	StarterPlayer = {
		name = "StarterPlayer",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "StarterPlayer",
            type = "type.name",
            child = {
                StarterPlayerScripts = {
                    name = "StarterPlayerScripts",
                    type = "type.library",
                    kind = "child",
                    value = {
                        [1] = "StarterPlayerScripts",
                        type = "type.name"
                    }
                },
                StarterCharacterScripts = {
                    name = "StarterCharacterScripts",
                    type = "type.library",
                    kind = "child",
                    value = {
                        [1] = "StarterCharacterScripts",
                        type = "type.name"
                    }
                }
            }
		}
	}
}

m.playerChild = {
	Backpack = {
		name = "Backpack",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "Backpack",
            type = "type.name",
            child = {}
		}
	},
	Character = {
		name = "Character",
		type = "type.library",
		kind = "property",
		value = {
			[1] = "Model",
            type = "type.name",
            child = {
                Humanoid = {
                    name = "Humanoid",
                    type = "type.library",
                    kind = "child",
                    value = {
                        [1] = "Humanoid",
                        type = "type.name"
                    }
                },
                HumanoidRootPart = {
                    name = "HumanoidRootPart",
                    type = "type.library",
                    kind = "child",
                    value = {
                        [1] = "Part",
                        type = "type.name"
                    }
                },
            }
		},
	},
	PlayerGui = {
		name = "PlayerGui",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "PlayerGui",
            type = "type.name",
            child = {}
		}
	},
	PlayerScripts = {
		name = "PlayerScripts",
		type = "type.library",
		kind = "child",
		value = {
			[1] = "PlayerScripts",
            type = "type.name",
            child = {}
		}
	},
}

m.customType = {
    WithMeta = {
        type = "type.alias",
        name = {
            type = "type.alias.name",
            [1] = "WithMeta"
        },
        generics = {
            type = "type.generics",
            {
                type = "type.parameter",
                [1] = "T",
            },
            {
                type = "type.parameter",
                [1] = "M",
            }
        },
        value = {
            type = "type.meta",
            [1] = {
                type = "type.name",
                [1] = "T"
            },
            [2] = {
                type = "type.name",
                [1] = "M"
            }
        }
    }
}

m.customType.WithMeta.generics[1].replace = {m.customType.WithMeta.value[1]}
m.customType.WithMeta.generics[2].replace = {m.customType.WithMeta.value[2]}

for _, alias in pairs(m.customType) do
    util.setTypeParent(alias)
end

local deprecated = {
    ["delay"] = true,
    ["elapsedTime"] = true,
    ["spawn"] = true,
    ["wait"] = true,
    ["ypcall"] = true,
    ["collectgarbage"] = true,
}

local typeEnums = {
    {
        text = "\"string\"",
        label = "\"string\""
    },
    {
        text = "\"number\"",
        label = "\"number\""
    },
    {
        text = "\"boolean\"",
        label = "\"boolean\""
    },
    {
        text = "\"function\"",
        label = "\"function\""
    },
    {
        text = "\"table\"",
        label = "\"table\""
    },
    {
        text = "\"thread\"",
        label = "\"thread\""
    },
    {
        text = "\"nil\"",
        label = "\"nil\""
    },
    {
        text = "\"vector\"",
        label = "\"vector\""
    },
    {
        text = "\"userdata\"",
        label = "\"userdata\""
    }
}

local function loadLibLocale(langID, result)
	result = result or {}
    -- local path = (ROOT / 'locale' / langID / 'library.lua'):string()
    -- local localeContent = util.loadFile(path)
    -- if localeContent then
    --     xpcall(lloader, log.error, localeContent, path, result)
    -- end
    return result
end

function m.init()
    if m.initialized then
        return
    end
    local libDoc = loadLibLocale('en-US')
	if lang.id ~= 'en-US' then
		loadLibLocale(lang.id, libDoc)
	end
    local parser = require("parser")
    m.global = {}
    m.testez = {}
    for tbl, file in pairs({[m.global] = "env.luau", [m.testez] = "3rd/testez.luau"}) do
        local state = parser:compile(util.loadFile(ROOT / "def" / file), "lua")
        if state then
            state.ast.uri = tostring(ROOT / "def" / file)
            local env
            for _, alias in ipairs(state.ast.types) do
                if alias.name[1] == "ENV" then
                    env = alias
                    break
                end
            end
            for _, g in ipairs(env.value) do
                tbl[g.key[1]] = {
                    name = g.key[1],
                    description = libDoc[g.key],
                    kind = "global",
                    type = "type.library",
                    value = g.value,
                    deprecated = deprecated[g.key[1]]
                }
                if g.key[1] == "setmetatable" then
                    g.value.argCount = 2
                end
                g.value.parent = tbl[g.key[1]]
                if g.value.type == "type.table" then
                    for _, field in ipairs(g.value) do
                        field.description = libDoc[g.key[1] .. "." .. field.key[1]]
                    end
                end
            end
        end
    end
    m.global["type"].value.enums = typeEnums
    m.object = {}
    for tp in pairs(m.primitiveTypes) do
        m.object[tp] = {
            child = {}
        }
    end
    for _, field in ipairs(m.global.string.value) do
        field = util.shallowCopy(field)
        field.type = "type.library"
        field.value = util.deepCopy(field.value)
        field.method = true
        field.name = field.key[1]
        util.setTypeParent(field)
        m.object.string.child[#m.object.string.child+1] = field
    end
    for libPath in fs.pairs(ROOT / "def" / "3rd") do
        local state = parser:compile(util.loadFile(libPath), "lua")
        if state then
            state.ast.uri = tostring(libPath)
            if state.ast.types then
                for _, alias in ipairs(state.ast.types) do
                    if alias.export then
                        m.customType[alias.name[1]] = alias
                    end
                end
            end
        end
    end
	m.initialized = true
end

return m