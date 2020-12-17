local json = require 'json'
local xml = require 'xml'
local fs = require 'bee.filesystem'
local rojo = require 'rojo'
local config = require 'config'
local rpc = require 'rpc'
local lang = require 'language'

local rbxApi = {}

local UnscriptableTags = {
    NotScriptable = true,
    Deprecated = true,
    Hidden = true,
}

local Types = {
    Variant = "any",
    bool = "boolean",
    void = "nil",
    int = "integer",
    int64 = "integer",
    double = "number",
    float = "number",
    Function = "function"
}

rbxApi.AllMembers = {}

rbxApi.Constructors = {}

rbxApi.TypedFunctions = {
    FindFirstAncestorWhichIsA = true,
    FindFirstChildWhichIsA = true,
    FindFirstAncestorOfClass = true,
    FindFirstChildOfClass = true,
    GetService = true
}

rbxApi.TypedTableFunctions = {
    GetConnectedParts = "BasePart",
    GetJoints = "JointInstance",
    GetTouchingParts = "BasePart",
    GetGuiObjectsAtPosition = "GuiObject",
    GetPartsObscuringTarget = "BasePart",
    GetCurrentPlayers = "Player",
    GetEnumItems = "EnumItem",
    getEnums = "Enum",
    GetGroupsAsync = "Dictionary",
    GetAccessories = "Accessory",
    GetPlayingAnimationTracks = "AnimationTrack",
    GetPlayers = "Player",
    Negate = "NegateOperation",
    Separate = "UnionOperation",
    GetTeams = "Team",
    GetConnectedGamepads = "Enum.UserInputType",
    GetGamepadState = "InputObject",
    GetKeysPressed = "InputObject",
    GetMouseButtonsPressed = "InputObject",
    GetNavigationGamepads = "InputObject",
    GetSupportedGamepadKeyCodes = "Enum.KeyCode",
    FindPartsInRegion3 = "BasePart",
    FindPartsInRegion3WithIgnoreList = "BasePart",
    FindPartsInRegion3WithWhiteList = "BasePart",
    GetWaypoints = "PathWaypoint",
    GetTags = "string",
    GetCollisionGroups = "Dictionary"
}

rbxApi.CorrectReturns = {
    Instance = {
        GetDescendants = "Objects"
    },
    Players = {
        LocalPlayer = "Player",
    },
    Player = {
        GetMouse = "Mouse"
    },
    Workspace = {
        Terrain = "Terrain"
    },
    Plugin = {
        CreateDockWidgetPluginGui = "DockWidgetPluginGui",
        CreatePluginAction = "PluginAction",
        CreatePluginMenu = "PluginMenu",
        CreateToolbar = "PluginToolbar",
        GetMouse = "PluginMouse"
    },
    PluginToolbar = {
        CreateButton = "PluginToolbarButton"
    },
    PluginMenu = {
        AddNewAction = "PluginAction"
    },
    TweenService = {
        Create = "Tween"
    }
}

rbxApi.CorrectParams = {
    AnimationController = {
        LoadAnimation = {animation = "Animation"}
    },
    Animator = {
        LoadAnimation = {animation = "Animation"}
    },
    AssetService = {
        CreatePlaceInPlayerInventoryAsync = {player = "Player"}
    },
    Chat = {
        FilterStringAsync = {playerFrom = "Player", playerTo = "Player"},
        FilterStringForBroadcast = {playerFrom = "Player"}
    },
    GuiService = {
        InspectPlayerFromHumanoidDescription = {humanoidDescription = "HumanoidDescription"}
    },
    Humanoid = {
        AddAccessory = {accessory = "Instance"},
        EquipTool = {tool = "Tool"},
        GetBodyPartR15 = {part = "BasePart"},
        GetLimb = {limb = "BasePart"},
        LoadAnimation = {animation = "Animation"},
        MoveTo = {part = "BasePart"},
        ReplaceBodyPartR15 = {part = "BasePart"},
        ApplyDescription = {humanoidDescription = "HumanoidDescription"}
    },
    Keyframe = {
        AddMarker = {marker = "KeyframeMarker"},
        AddPose = {pose = "Pose"},
        RemoveMarker = {market = "KeyframeMarker"},
        RemovePose = {pose = "Pose"},
    },
    KeyframeSequence = {
        AddKeyframe = {keyframe = "Keyframe"},
        RemoveKeyframe = {keyframe = "Keyframe"},
        RegisterActiveKeyframeSequence = {keyframeSequence = "KeyframeSequence"},
        RegisterKeyframeSequence = {keyframeSequence = "KeyframeSequence"},
    },
    LocalizationService = {
        GetTranslatorForPlayer = {player = "Player"},
        GetCountryRegionForPlayerAsync = {player = "Player"},
        GetTranslatorForPlayerAsync = {player = "Player"},
    },
    MarketplaceService = {
        PromptGamePassPurchase = {player = "Player"},
        PromptPremiumPurchase = {player = "Player"},
        PromptProductPurchase = {player = "Player"},
        PromptPurchase = {player = "Player"},
        PromptSubscriptionCancellation = {player = "Player"},
        PromptSubscriptionPurchase = {player = "Player"},
        IsPlayerSubscribed = {player = "Player"},
        PlayerOwnsAsset = {player = "Player"}
    },
    BasePart = {
        CanCollideWith = {part = "BasePart"},
        SetNetworkOwner = {playerInstance = "Player"}
    },
    Seat = {
        Sit = {humanoid = "Humanoid"}
    },
    VehicleSeat = {
        Sit = {humanoid = "Humanoid"}
    },
    PhysicsService = {
        CollisionGroupContainsPart = {part = "BasePart"},
        SetPartCollisionGroup = {part = "BasePart"},
    },
    Player = {
        LoadCharacterWithHumanoidDescription = {humanoidDescription = "HumanoidDescription"},
    },
    Players = {
        GetPlayerFromCharacter = {character = "Model"}
    },
    PolicyService = {
        GetPolicyInfoForPlayerAsync = {player = "Player"}
    },
    Pose = {
        AddSubPose = {pose = "Pose"},
        RemoveSubPose = {pose = "Pose"},
    },
    RemoteEvent = {
        FireClient = {player = "Player"}
    },
    RemoteFunction = {
        InvokeClient = {player = "Player"}
    },
    SocialService = {
        PromptGameInvite = {player = "Player"},
        CanSendGameInviteAsync = {player = "Player"}
    },
    SoundService = {
        PlayLocalSound = {sound = "Sound"}
    },
    TeleportService = {
        SetTeleportGui = {gui = "GuiObject"},
        Teleport = {player = "Player", customLoadingScreen = "GuiObject"},
        TeleportToPlaceInstance = {player = "Player", customLoadingScreen = "GuiObject"},
        TeleportToPrivateServer = {players = "Array<Player>", customLoadingScreen = "GuiObject"},
        TeleportToSpawnByName = {player = "Player", customLoadingScreen = "GuiObject"},
        TeleportPartyAsync = {players = "Array<Player>", customLoadingScreen = "GuiObject"}
    },
}

rbxApi.TupleReturns = {
    Color3 = {
        ToHSV = {"number", "number", "number"},
        toHSV = {"number", "number", "number"}
    },
    Camera = {
        WorldToScreenPoint = {"number", "number", "number", "boolean"},
        WorldToViewportPoint = {"number", "number", "number", "boolean"}
    },
    GuiService = {
        GetGuiInset = {"Vector2", "Vector2"}
    },
    BasePart = {
        CanSetNetworkOwnership = {"boolean", "string"}
    },
    Model = {
        GetBoundingBox = {"CFrame", "Vector3"}
    },
    WorldRoot = {
        FindPartOnRay = {"BasePart", "Vector3", "Vector3", "Enum.Material"},
        FindPartOnRayWithIgnoreList = {"BasePart", "Vector3", "Vector3", "Enum.Material"},
        FindPartOnRayWithWhiteList = {"BasePart", "Vector3", "Vector3", "Enum.Material"},
        findPartOnRay = {"BasePart", "Vector3", "Vector3", "Enum.Material"},
    },
    Players = {
        GetUserThumbnailAsync = {"string", "boolean"}
    },
    SoundService = {
        GetListener = {"Enum.ListenerType", "any"}
    },
    TeleportService = {
        GetPlayerPlaceInstanceAsync = {"boolean", "integer", "string"}
    },
    UserInputService = {
        GetDeviceRotation = {"number", "CFrame"}
    },
    CFrame = {
        ToOrientation = {"number", "number", "number"},
        ToEulerAnglesYXZ = {"number", "number", "number"},
        GetComponents = {"number", "number", "number", "number", "number", "number", "number", "number", "number", "number", "number", "number"},
        components = {"number", "number", "number", "number", "number", "number", "number", "number", "number", "number", "number", "number"},
        ToEulerAnglesXYZ = {"number", "number", "number"},
        toEulerAnglesXYZ = {"number", "number", "number"},
        ToAxisAngle = {"Vector3", "number"},
        toAxisAngle = {"Vector3", "number"}
    }
}

rbxApi.EventsParameters = {
    Equipped = {Tool = {"mouse: Mouse"}},
    PlayerMembershipChanged = {Players = {"player: Player"}},
    TouchMoved = {UserInputService = {"input: InputObject", "gameProcessedEvent: boolean"}},
    TextBoxFocusReleased = {UserInputService = {"textboxReleased: TextBox"}},
    Hit = {Explosion = {"part: BasePart", "distance: number"}},
    LocalToolEquipped = {ContextActionService = {"toolEquipped: Tool"}},
    PlayerRejoining = {Players = {"player: Player"}},
    AnimationPlayed = {
        AnimationController = {"animationTrack: AnimationTrack"},
        Animator = {"animationTrack: AnimationTrack"},
        Humanoid = {"animationTrack: AnimationTrack"}
    },
    DialogChoiceSelected = {Dialog = {"player: Player", "dialogChoice: DialogChoice"}},
    PromptPurchaseRequested = {MarketplaceService = {"player: Player", "assetId: integer", "equipIfPurchased: boolean", "currencyType: Enum.CurrencyType"}},
    PromptSubscriptionPurchaseRequested = {MarketplaceService = {"player: Player", "subscriptionId: integer"}},
    PromptSubscriptionPurchaseFinished = {MarketplaceService = {"player: Player", "subscriptionId: integer", "wasPurchased: boolean"}},
    PromptSubscriptionCancellationFinished = {MarketplaceService = {"player: Player", "subscriptionId: integer", "wasCancelled: boolean"}},
    PromptGamePassPurchaseRequested = {MarketplaceService = {"player: Player", "gamePassId: integer"}},
    PlayerChatted = {Players = {"chatType: Enum.PlayerChatType", "player: Player", "message: string", "targetPlayer: Player"}},
    PlayerAdded = {
        Players = {"player: Player"},
        Team = {"player: Player"},
    },
    RightMouseClick = {ClickDetector = {"playerWhoClicked: Player"}},
    TouchStarted = {UserInputService = {"input: InputObject", "gameProcessedEvent: boolean"}},
    InputChanged = {
        GuiObject = {"input: InputObject"}, {"InputObject", "boolean"},
        UserInputService = {"input: InputObject", "gameProcessedEvent: boolean"}
    },
    LocalToolUnequipped = {ContextActionService = {"toolUnequipped: Tool"}},
    InputBegan = {
        GuiObject = {"input: InputObject"},
        UserInputService = {"input: InputObject", "gameProcessedEvent: boolean"}
    },
    FocusLost = {TextBox = {"enterPressed: boolean", "inputThatCausedFocusLoss: InputObject"}},
    OnServerEvent = {RemoteEvent = {"player: Player", "arguments: Tuple"}},
    PlayerRemoved = {Team = {"player: Player"}},
    PromptPurchaseFinished = {MarketplaceService = {"player: Player", "assetId: integer", "isPurchased: boolean"}},
    MouseHoverLeave = {ClickDetector = {"playerWhoHovered: Player"}},
    Chatted = {
        Chat = {"part: BasePart", "message: string", "color: Enum.ChatColor"},
        Player = {"message: string", "recipient: Player"}
    },
    MouseClick = {ClickDetector = {"playerWhoClicked: Player"}},
    PlayerRemoving = {Players = {"player: Player"}},
    TouchEnded = {
        BasePart = {"otherPart: BasePart"},
        UserInputService = {"input: InputObject", "gameProcessedEvent: boolean"}
    },
    PlayerDisconnecting = {Players = {"player: Player"}},
    NativePurchaseFinished = {MarketplaceService = {"player: Player", "productId: string", "wasPurchased: boolean"}},
    CharacterAppearanceLoaded = {Player = {"character: Model"}},
    CharacterAdded = {Player = {"character: Model"}},
    PromptGamePassPurchaseFinished = {MarketplaceService = {"player: Player", "gamePassId: integer", "wasPurchased: boolean"}},
    CharacterRemoving = {Player = {"character: Model"}},
    PromptProductPurchaseRequested = {MarketplaceService = {"player: Player", "productId: integer", "equipIfPurchased: boolean", "currencyType: Enum.CurrencyType"}},
    MouseHoverEnter = {ClickDetector = {"playerWhoHovered: Player"}},
    TextBoxFocused = {UserInputService = {"textboxFocused: TextBox"}},
    Activated = {GuiButton = {"inputObject: InputObject", "clickCount: integer"}},
    InputEnded = {
        GuiObject = {"input: InputObject"}, {"InputObject", "boolean"},
        UserInputService = {"input: InputObject", "gameProcessedEvent: boolean"}
    },
    Touched = {
        Humanoid = {"touchingPart: BasePart", "humanoidPart: BasePart"},
        BasePart = {"otherPart: BasePart"}},
    PlayerConnecting = {Players = {"player: Player"}},
    Seated = {Humanoid = {"active: boolean", "currentSeatPart: Seat"}}
}

rbxApi.ClassDocs = {
    Instance = {
        Name = "A non-unique identifier of the Instance.",
        ChildAdded = "Fires when an object is parented to this Instance.",
        ChildRemoved = "Fires when a child is removed from this Instance.",
    },
    BasePart = {
        CollisionGroupId = "Describes the automatically-set ID number of a part’s collision group.",
        Position = "Describes the position of the part in the world.",
        Size = "Determines the dimensions of a part (length, width, height).",
        RotVelocity = "Determines a part’s change in orientation over time."
    }
}

rbxApi.FunctionVariants = {
    new = {
        BrickColor = {"val: number", "r: number, g: number, b: number", "val: string", "color: Color3"},
        CFrame = {
            "pos: Vector3", "pos: Vector3, lookAt: Vector3", "x: number, y: number, z: number",
            "x: number, y: number, z: number, qX: number, qY: number, qZ: number, qW: number",
            "x: number, y: number, z: number, R00: number, R01: number, R02: number, R10: number, R11: number, R12: number, R20: number, R21: number, R22: number",
        },
        ColorSequence = {"c: Color3", "c0: Color3, c1: Color3", "keypoints: Array<ColorSequenceKeypoint>"},
        NumberRange = {"value: number", "min: number, max: number"},
        NumberSequence = {"n: number", "n0: number, n1: number", "keypoints: Array<NumberSequenceKeypoint>"},
        PhysicalProperties = {
            "material: Enum.Material",
            "density: number, friction: number, elasticy: number",
            "density: number, friction: number, elasticy: number, frictionWeight: number, elasticyWeight: number"
        },
        Rect = {"min: Vector2, max: Vector2", "minX: number, minY: number, maxX: number, maxY: number"},
        UDim2 = {"xScale: number, xOffset: number, yScale: number, yOffset: number", "x: UDim, y: UDim"}
    }
}

rbxApi.DeprecatedQuickFix = {
    AppearanceDidLoad = "CharacterAppearanceLoaded",
    BackgroundColor = "BackgroundColor3",
    BindActionToInputTypes = "BindAction",
    BorderColor = "BorderColor3",
    Color = "Color3",
    ComputeRawPathAsync = "FindPathAsync",
    ComputeSmoothPathAsync = "FindPathAsync",
    CoordinateFrame = "CFrame",
    DevelopmentLanguage = "SourceLocaleId",
    Elasticity = "CustomPhysicalProperties.Elasticity",
    FilterStringForPlayerAsync = "FilterStringAsync",
    FontSize = "TextSize",
    Friction = "CustomPhysicalProperties.Friction",
    FromAxis = "fromAxis",
    FromNormalId = "fromNormalId",
    GetAxis = "Axis",
    GetKeyframeSequence = "GetKeyframeSequenceAsync",
    GetKeyframeSequenceById = "GetKeyframeSequenceAsync",
    GetModelCFrame = "GetPrimaryPartCFrame",
    GetModelSize = "GetExtentsSize",
    GetPointCoordinates = "GetWaypoints",
    GetRemoteBuildMode = "RunService.IsServer",
    GetSecondaryAxis = "SecondaryAxis",
    GetString = "GetTranslator",
    Insert = "LoadAsset",
    Interpolate = "TweenService.Create",
    IsBestFriendsWith = "IsFriendsWith",
    IsDisabled = "GetBadgeInfoAsync",
    ItemAdded = "GetInstanceAddedSignal",
    ItemChanged = "Changed",
    ItemRemoved = "GetInstanceRemovedSignal",
    LocalSimulationTouched = "Touched",
    MaskWeight = "Weight",
    MinDistance = "EmitterSize",
    NumPlayers = "GetPlayers",
    OnClose = "BindToClose",
    Pitch = "PlaybackSpeed",
    PlayerHasPass = "MarketplaceService.UserOwnsGamePassAsync",
    Preload = "PreloadAsync",
    PromptProductPurchaseFinished = "PromptPurchaseFinished",
    Remove = "Destroy",
    RemoveKey = "RemoveEntry",
    ResetPlayerGuiOnSpawn = "ResetOnSpawn",
    Rotation = "Orientation",
    SetAxis = "Axis",
    GetContents = "GetEntries",
    SetContents = "SetEntries",
    SetCustomSortFunction = "SortOrder",
    SetEntry = "SetEntries",
    SetSecondaryAxis = "SecondaryAxis",
    SpecificGravity = "CustomPhysicalProperties.Density",
    StoppedTouching = "TouchEnded",
    SurfaceColor = "SurfaceColor3",
    TextColor = "TextColor3",
    TextWrap = "TextWrapped",
    UserHasBadge = "UserHasBadgeAsync",
    UserHeadCFrame = "GetUserCFrame",
    VIPServerId = "PrivateServerId",
    VIPServerOwnerId = "PrivateServerOwnerId",
    VelocitySpread = "SpreadAngle",
    WorldRotation = "WorldOrientation",
    addItem = "AddItem",
    angularvelocity = "AngularVelocity",
    archivable = "Archivable",
    b = "B",
    bindButton = "BindButton",
    breakJoints = "BreakJoints",
    brickColor = "BrickColor",
    cframe = "CFrame",
    changed = "Changed",
    childAdded = "ChildAdded",
    children = "GetChildren",
    className = "ClassName",
    clone = "Clone",
    components = "GetComponents",
    connect = "Connect",
    connected = "Connected",
    destroy = "Destroy",
    disconnect = "Disconnect",
    findFirstChild = "FindFirstChild",
    findPartOnRay = "FindPartOnRay",
    findPartsInRegion3 = "FindPartsInRegion3",
    fire = "Fire",
    focus = "Focus",
    force = "Force",
    formFactor = "FormFactor",
    g = "G",
    getButton = "GetButton",
    getChildren = "GetChildren",
    getMass = "GetMass",
    getMinutesAfterMidnight = "GetMinutesAfterMidnight",
    getPlayerFromCharacter = "GetPlayerFromCharacter",
    getPlayers = "GetPlayers",
    getService = "GetService",
    hit = "Hit",
    inverse = "Inverse",
    isA = "IsA",
    isDescendantOf = "IsDescendantOf",
    isFriendsWith = "IsFriendsWith",
    isPlaying = "IsPlaying",
    keyDown = "KeyDown",
    lastForce = "GetLastForce",
    lerp = "Lerp",
    lighting = "Lighting",
    loadAnimation = "LoadAnimation",
    loadAsset = "LoadAsset",
    localPlayer = "LocalPlayer",
    location = "Location",
    lookVector = "LookVector",
    magnitude = "Magnitude",
    makeJoints = "MakeJoints",
    maxForce = "MaxForce",
    maxHealth = "MaxHealth",
    maxTorque = "MaxTorque",
    mouseClick = "MouseClick",
    move = "Move",
    moveTo = "MoveTo",
    numPlayers = "NumPlayers",
    p = "Position",
    part1 = "Part1",
    pause = "Pause",
    play = "Play",
    playerFromCharacter = "GetPlayerFromCharacter",
    players = "Players",
    pointToObjectSpace = "PointToObjectSpace",
    pointToWorldSpace = "PointToWorldSpace",
    position = "Position",
    r = "R",
    remove = "Destroy",
    resize = "Resize",
    rightVector = "RightVector",
    service = "GetService",
    setMinutesAfterMidnight = "SetMinutesAfterMidnight",
    size = "Size",
    stop = "Stop",
    takeDamage = "TakeDamage",
    target = "Target",
    toAxisAngle = "ToAxisAngle",
    toEulerAnglesXYZ = "ToEulerAnglesXYZ",
    toObjectSpace = "ToObjectSpace",
    toWorldSpace = "ToWorldSpace",
    touched = "Touched",
    unit = "Unit",
    upVector = "UpVector",
    userId = "UserId",
    vectorToObjectSpace = "VectorToObjectSpace",
    vectorToWorldSpace = "VectorToWorldSpace",
    velocity = "Velocity",
    wait = "Wait",
    workspace = "Workspace",
    x = "X",
    y = "Y",
    z = "Z"
 }

rbxApi.PlayerChilds = {
    Backpack = {
        name = "Backpack",
        type = "Backpack",
        child = {},
        obj = true
    },
    PlayerGui = {
        name = "PlayerGui",
        type = "PlayerGui",
        child = {},
        obj = true
    },
    Character = {
        name = "Character",
        type = "Model",
        child = {
            Humanoid = {
                name = "Humanoid",
                type = "Humanoid",
                child = {},
                obj = true
            },
            HumanoidRootPart = {
                name = "HumanoidRootPart",
                type = "Part",
                child = {},
                obj = true
            }
        },
        obj = true
    },
    PlayerScripts = {
        name = "PlayerScripts",
        type = "PlayerScripts",
        child = {},
        obj = true
    }
}

rbxApi.DataModelIgnoreNames = {}

rbxApi.DataModelChilds = {
    StarterPlayer = {
        name = "StarterPlayer",
        type = "StarterPlayer",
        child = {
            StarterCharacterScripts = {
                name = "StarterCharacterScripts",
                type = "StarterCharacterScripts",
                child = {},
                obj = true
            },
            StarterPlayerScripts = {
                name = "StarterPlayerScripts",
                type = "StarterPlayerScripts",
                child = {},
                obj = true
            }
        },
        obj = true
    }
}

for _, name in pairs{
    "Players",
    "Lighting",
    "ReplicatedFirst",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterGui",
    "StarterPack",
    "SoundService"
} do
    rbxApi.DataModelChilds[name] = {
        name = name,
        type = name,
        child = {},
        obj = true
    }
end

local function readFile(path)
    local file = io.open(tostring(path))
    local contents = file:read("*a")
    file:close()
    return contents
end

local function fixType(name, category, returns)
    if category == "Enum" then
        return "Enum." .. name
    end
    if Types[name] then
        return Types[name]
    end
    if name == "Tuple" then
        if returns then
            return "any"
        end
        return "..."
    end
    return name
end

local function mergeTable(tbl1, tbl2)
    for k, v in pairs(tbl2) do
        if type(k) == "string" then
            tbl1[k] = v
        else
            table.insert(tbl1, v)
        end
    end
end

function rbxApi:loadApiJson()
    if not self.Api then
        local api = json.decode(readFile(ROOT / "rbx" / "API-Dump.json"))
        local datatypes = json.decode(readFile(ROOT / "rbx" / "datatypes.json"))
        for key, value in pairs(datatypes) do
            api[key] = value
        end
        self.Api = api
        self:parseReflectionMetadata()
        self:parseDataTypesMetadata()
    end
    return self.Api
end

function rbxApi:parseReflectionMetadata()
    local htmlToMarkdown = json.decode(readFile(ROOT / "rbx" / "html_md.json"))
    local data = xml.parser.parse(readFile(ROOT / "rbx" / "ReflectionMetadata.xml"))
    local classes = xml.getAttr(data.children[1], "class", "ReflectionMetadataClasses")
    xml.forAttr(classes, "class", "ReflectionMetadataClass", function(class)
        local properties = xml.getTag(class, "Properties")
        local className = xml.getChild(xml.getAttr(properties, "name", "Name"), "text")
        local summary = xml.getChild(xml.getAttr(properties, "name", "summary"), "text")
        local docs = self.ClassDocs[className] or {}
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
        self.ClassDocs[className] = docs
    end)
end

function rbxApi:parseDataTypesMetadata()
    local data = xml.parser.parse(readFile(ROOT / "rbx" / "AutocompleteMetadata.xml"))
    local items = xml.getTag(data, "StudioAutocomplete")
    xml.forTag(items, "ItemStruct", function(struct)
        local className = struct.attrs.name
        if className == "EventInstance" then
            className = "RBXScriptSignal"
        elseif className == "RobloxScriptConnection" then
            className = "RBXScriptConnection"
        end
        local docs = self.ClassDocs[className] or {}
        xml.forTag(struct, "Function", function(func)
            local memberName = func.attrs.name
            if memberName == "new" and self.FunctionVariants.new[className] then
                return
            end
            local description = xml.getChild(xml.getTag(func, "description"), "text")
            if description then
                docs[memberName] = description
            end
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
        self.ClassDocs[className] = docs
    end)
end

function rbxApi:getClassNames()
    if not self.ClassNames then
        self.ClassNames = {}
        local api = self:loadApiJson()
        for _, rbxClass in pairs(api.Classes) do
            if rbxClass.Tags then
                for _, tag in pairs(rbxClass.Tags) do
                    if UnscriptableTags[tag] then
                        goto CONTINUE
                    end
                end
            end
            self.ClassNames[rbxClass.Name] = rbxClass.Superclass
            ::CONTINUE::
        end
    end
    return self.ClassNames
end

function rbxApi:isInstance(class)
    if self.ClassNames[class] then
        return true
    end
end

function rbxApi:isA(class, super)
    if not class then
        return
    end
    if class == super then
        return true
    elseif self.ClassNames[class] then
        if self.ClassNames[class] == super then
            return true
        else
            return self:isA(self.ClassNames[class], super)
        end
    end
    return false
end

function rbxApi:getCreatableInstances()
    if not self.CreatableInstances then
        self.CreatableInstances = {}
        local api = self:loadApiJson()
        for _, rbxClass in pairs(api.Classes) do
            if rbxClass.Tags then
                for _, tag in pairs(rbxClass.Tags) do
                    if UnscriptableTags[tag] or tag == "NotCreatable" then
                        goto CONTINUE
                    end
                end
            end
            self.CreatableInstances[rbxClass.Name] = true
            ::CONTINUE::
        end
    end
    return self.CreatableInstances
end

function rbxApi:getServices()
    if not self.Services then
        self.Services = {
            UserGameSettings = true
        }
        local api = self:loadApiJson()
        for _, rbxClass in pairs(api.Classes) do
            local _continue = false
            if rbxClass.Tags then
                for _, tag in pairs(rbxClass.Tags) do
                    if tag == "Service" then
                        _continue = true
                    end
                end
                for _, tag in pairs(rbxClass.Tags) do
                    if UnscriptableTags[tag] then
                        _continue = false
                    end
                end
            end
            if _continue then
                self.Services[rbxClass.Name] = true
            end
        end
    end
    return self.Services
end

function rbxApi:generateEnums(argName, type)
    local enums = {}
    local list = nil
    if type == 1 then
        list = self:getClassNames()
    elseif type == 2 then
        list = self:getServices()
    elseif type == 3 then
        list = self:getCreatableInstances()
    elseif type == 4 then
        for name, enumType in pairs(argName) do
            for _, enum in pairs(self.Api.Enums) do
                if enum.Name == enumType then
                    for _, item in pairs(enum.Items) do
                        table.insert(enums, {
                            name = name,
                            enum = '"' .. item.Name .. '"'
                        })
                    end
                end
            end
        end
        return enums
    end
    for rbxClass in pairs(list) do
        local docs = nil
        if self.ClassDocs[rbxClass] then
            docs = self.ClassDocs[rbxClass].__Summary
        end
        table.insert(enums, {
            name = argName,
            enum = '"' .. rbxClass .. '"',
            description = docs,
            rbxclass = type <= 3
        })
    end
    return enums
end

rbxApi.ParamsEnums = {
    ServiceProvider = {
        GetService = rbxApi:generateEnums("className", 2)
    },
    Instance = {
        new = rbxApi:generateEnums("className", 3),
        IsA = rbxApi:generateEnums("className", 1),
        FindFirstAncestorWhichIsA = rbxApi:generateEnums("className", 1),
        FindFirstChildWhichIsA = rbxApi:generateEnums("className", 1),
        FindFirstAncestorOfClass = rbxApi:generateEnums("className", 1),
        FindFirstChildOfClass = rbxApi:generateEnums("className", 1),
    }
}


function rbxApi:getEnums(data)
    for _, enum in pairs(self.Api.Enums) do
        local items = {}
        data[enum.Name] = {
            name = enum.Name,
            type = "Enum",
            child = items,
        }
        for _, item in pairs(enum.Items) do
            items[item.Name] = {
                name = item.Name,
                type = "EnumItem",
                child = {
                    ["EnumType"] = data[enum.Name]
                }
            }
        end
    end
end

rbxApi.DeprecatedMembers = {}

local function addDeprecated(memberName, className)
    if memberName == "NumPlayers" then
        return
    end
    rbxApi.DeprecatedMembers[memberName] = rbxApi.DeprecatedMembers[memberName] or {}
    rbxApi.DeprecatedMembers[memberName][className] = true
end

local function getCorrectParam(className, memberName, paramName)
    if rbxApi.CorrectParams[className]
    and rbxApi.CorrectParams[className][memberName]
    and rbxApi.CorrectParams[className][memberName][paramName]
    then
        return rbxApi.CorrectParams[className][memberName][paramName]
    end
end

local MemberSecurity = {
    None = true,
    PluginSecurity = true
}

function rbxApi:getMembers(members, methods, className)
    local data = {}
    for _, member in pairs(members) do
        local tags = {}
        local hidden = false
        local docs = nil
        local correctType = nil
        if member.Deprecated then
            addDeprecated(member.Name, className)
            hidden = true
        end
        if member.Tags then
            for _, tag in pairs(member.Tags) do
                if tag == "Deprecated" then
                    addDeprecated(member.Name, className)
                    hidden = true
                elseif tag == "Hidden" then
                    hidden = true
                elseif tag == "NotScriptable" then
                    goto CONTINUE
                end
                tags[#tags+1] = tag
            end
        end
        if member.Security then
            if type(member.Security) == "string" and not MemberSecurity[member.Security] then
                goto CONTINUE
            elseif type(member.Security) == "table" then
                if not MemberSecurity[member.Security.Read] then
                    goto CONTINUE
                end
            end
        end
        if self:isInstance(className) then
            self.AllMembers[member.Name] = true
        end
        if self.ClassDocs[className] then
            docs = self.ClassDocs[className][member.Name]
        else
            for class, _docs in pairs(self.ClassDocs) do
                if rbxApi:isA(class, className) then
                    if _docs[member.Name] then
                        docs = _docs[member.Name]
                    end
                end
            end
        end
        if #tags > 0 then
            docs = (docs or "") .. "\n\n" .. "tags: " .. table.concat(tags, ", ") .. "."
        end
        if self.CorrectReturns[className] and self.CorrectReturns[className][member.Name] then
            correctType = self.CorrectReturns[className][member.Name]
        end
        if member.MemberType == "Property" then
            if self:isInstance(className) then
                docs = (docs or "") .. ('\n\n[%s](%s/%s/%s)'):format(lang.script.HOVER_VIEW_DOCUMENTS, "https://developer.roblox.com/en-us/api-reference/property", className, member.Name)
            else
                docs = (docs or "") .. ('\n\n[%s](%s/%s)'):format(lang.script.HOVER_VIEW_DOCUMENTS, "https://developer.roblox.com/en-us/api-reference/datatype", className)
            end
            data[member.Name] = {
                name = member.Name,
                type = correctType or fixType(
                    member.ValueType.Name,
                    member.ValueType.Category
                ),
                child = {},
                description = docs,
                hidden = hidden
            }
        elseif member.MemberType == "Function" then
            local args = {}
            if methods then
                args[1] = {name = "self", type = "any"}
            end
            local returnType = "nil"
            if member.ReturnType then
                returnType = correctType or fixType(
                    member.ReturnType.Name,
                    member.ReturnType.Category,
                    true
                )
                if self.TypedTableFunctions[member.Name] then
                    returnType = returnType .. "<" .. self.TypedTableFunctions[member.Name] .. ">"
                end
            end
            local enumsParams = nil
            for _, param in pairs(member.Parameters) do
                if type(param.Type.Name) == "table" then
                    param.Type.Name = param.Type.Name[1]
                end
                if param.Type.Name == "..." then
                    table.insert(args, {
                        type = "..."
                    })
                else
                    if param.Type.Category == "Enum" then
                        enumsParams = enumsParams or {}
                        enumsParams[param.Name] = param.Type.Name
                    end
                    table.insert(args, {
                        name = param.Name,
                        default = param.Default or nil,
                        type = getCorrectParam(className, member.Name, param.Name) or fixType(
                            param.Type.Name,
                            param.Type.Category
                        )
                    })
                end
            end
            local enums = nil
            local variants
            if self.ParamsEnums[className] then
                enums = self.ParamsEnums[className][member.Name]
            end
            if enumsParams then
                enums = enums or {}
                mergeTable(enums, self:generateEnums(enumsParams, 4))
            end
            if self.FunctionVariants[member.Name] and self.FunctionVariants[member.Name][className] then
                local desc = {}
                variants = self.FunctionVariants[member.Name][className]
                for _, variant in pairs(self.FunctionVariants[member.Name][className]) do
                    desc[#desc+1] = "function " .. member.Name .. "(" .. variant .. ")"
                end
                desc = ([[
```lua
%s
```
                ]]):format(table.concat(desc, "\n"))
                docs = docs and desc .. "\n" .. docs or desc
            end
            local returns = {
                {type = returnType}
            }
            if rbxApi.TupleReturns[className] and rbxApi.TupleReturns[className][member.Name] then
                returns = {}
                for _, tp in pairs(rbxApi.TupleReturns[className][member.Name]) do
                    returns[#returns+1] = {type = tp}
                end
            end
            data[member.Name] = {
                name = member.Name,
                type = "function",
                args = args,
                returns = returns,
                child = {},
                description = docs,
                variants = variants,
                enums = enums,
                hidden = hidden,
                className = className
            }
        elseif member.MemberType == "Event" then
            self.EventsParameters[member.Name] = self.EventsParameters[member.Name] or {}
            if member.Parameters and #member.Parameters > 0 then
                if not self.EventsParameters[member.Name][className] then
                    local params = {}
                    for _, param in pairs(member.Parameters) do
                        table.insert(params, param.Name .. ": " .. fixType(
                            param.Type.Name,
                            param.Type.Category,
                            true
                        ))
                    end
                    self.EventsParameters[member.Name][className] = params
                end
            end
            local params = {}
            local waitFunc = nil
            if self.EventsParameters[member.Name][className] then
                waitFunc = {
                    name = "Wait",
                    type = "function",
                    args = {{name = "self", type = "any"}},
                    description = self.ClassDocs.RBXScriptSignal.Wait,
                    returns = {}
                }
                docs = docs or ""
                docs = ([[
```lua
%s
```
                ]]):format("-> " .. table.concat(self.EventsParameters[member.Name][className], ", ")) .. "\n\n" .. docs
                for _, param in pairs(self.EventsParameters[member.Name][className]) do
                    params[#params+1] = param:gsub("%:.+", "")
                    waitFunc.returns[#waitFunc.returns+1] = {
                        type = param:gsub("^[%w_]+%: ", "")
                    }
                end
            end
            docs = (docs or "") .. ('\n\n[%s](%s/%s/%s)'):format(lang.script.HOVER_VIEW_DOCUMENTS, "https://developer.roblox.com/en-us/api-reference/event", className, member.Name)
            data[member.Name] = {
                parentClass = className,
                name = member.Name,
                type = "RBXScriptSignal",
                child = {
                    ["Wait"] = waitFunc
                },
                description = docs,
                params = params,
                hidden = hidden
            }
        elseif member.MemberType == "Callback" then
            data[member.Name] = {
                name = member.Name,
                type = "Callback",
                child = {},
                description = docs,
                hidden = hidden
            }
        end
        ::CONTINUE::
    end
    if className == "DataModel" or className == "Player" then
        for name, child in pairs(self[className .. "Childs"]) do
            child.child["Parent"] = {
                name = "Parent",
                type = className,
                child = data
            }
            if self.ClassDocs[name] then
                child.description = self.ClassDocs[name].__Summary
            end
            data[name] = child
        end
    elseif self.DataModelChilds[className] then
        for name, child in pairs(self.DataModelChilds[className].child) do
            data[name] = child
        end
    end
    if className == "LuaSourceContainer" then
        data.Disabled = {
            name = "Disabled",
            type = "string"
        }
    end
    if className == "Enums" then
        self:getEnums(data)
    end
    return data
end

function rbxApi:addSuperMembers(className, superClass, libs)
    local members = libs[className]
    local superMembers = libs[superClass]
    if not superMembers then
        return
    end
    for name, member in pairs(superMembers) do
        if not members[name] then
            members[name] = member
        end
    end
    self:addSuperMembers(className, self:getClassNames()[superClass], libs)
end

function rbxApi:getTypes()
    if not self.Types then
        local types = {}
        local api = self:loadApiJson()
        for className in pairs(self:getClassNames()) do
            types[className] = true
        end
        for _, dataType in pairs(api.DataTypes) do
            types[dataType.Name] = true
        end
        for _, constructor in pairs(api.Constructors) do
            types[constructor.Name] = true
        end
        self.Types = types
    end
    return self.Types
end

local replicateToPlayer = {
    StarterPack = "Backpack",
    StarterGui = "PlayerGui",
    StarterPlayerScripts = "PlayerScripts",
    StarterCharacterScripts = "Character"
}

local function addPlayerChildren(children, parent)
    for childName, child in pairs(children) do
        local copy = {
            name = child.name,
            type = child.type,
            child = {},
            obj = true,
            path = child.path
        }
        for descendantName, descendant in pairs(child.child) do
            copy.child[descendantName] = descendant
        end
        copy.child["Parent"] = {
            name = "Parent",
            type = parent.type,
            child = parent.child,
            path = parent.path
        }
        parent.child[childName] = copy
    end
end

local function addChild(name, members, children, parent, path)
    rbxApi.DataModelIgnoreNames[name] = true
    local child = {
        name = name,
        type = members.className,
        child = {},
        obj = true,
        path = path .. "/" .. name
    }
    if parent then
        child.child["Parent"] = {
            name = "Parent",
            type = parent.type,
            child = parent.child,
            path = path
        }
    end
    children[name] = child
    if members.children then
        for childName, childMembers in pairs(members.children) do
            addChild(childName, childMembers, child.child, child, path .. "/" .. name)
        end
    end
    if replicateToPlayer[members.className] then
        addPlayerChildren(child.child, rbxApi.PlayerChilds[replicateToPlayer[members.className]])
    end
end

local function datamodelJsonDeprecated()
    for path in fs.current_path():list_directory() do
        if path:string():match("%.datamodel%.json$") then
            rpc:notify('window/showMessage', {
                type = 3,
                message = "Using .datamodel.json file is deprecated, you can now sync directly with Roblox Studio. [Learn more](https://devforum.roblox.com/t/roblox-lsp-full-intellisense-for-roblox-and-luau/717745)",
            })
            break
        end
    end
end

-- local function loadDatamodelJson()
--     local projectFileName = config.config.workspace.rojoProjectFile
--     if projectFileName ~= "" then
--         local path = fs.current_path() / (config.config.workspace.rojoProjectFile .. ".datamodel.json")
--         if fs.exists(path) then
--             local success, datamodel = pcall(json.decode, readFile(path:string()))
--             if success and datamodel.children then
--                 return datamodel
--             end
--         end
--     else
--         local datamodel = {}
--         for path in fs.current_path():list_directory() do
--             if path:string():match("%.datamodel%.json") then
--                 local success, data = pcall(json.decode, readFile(path:string()))
--                 if success and data.children then
--                     datamodel = table.merge(datamodel, data)
--                 end
--             end
--         end
--         if datamodel.children then
--             return datamodel
--         end
--     end
-- end

local defaultDatamodelChilds = table.deepCopy(rbxApi.DataModelChilds)
local defaultPlayerChilds = table.deepCopy(rbxApi.PlayerChilds)

function rbxApi:loadRojoProject(datamodel)
    self.DataModelChilds = table.deepCopy(defaultDatamodelChilds)
    self.PlayerChilds = table.deepCopy(defaultPlayerChilds)

    rbxApi.DataModelIgnoreNames = {}

    datamodelJsonDeprecated()

    -- local datamodelJson = loadDatamodelJson()
    -- if not datamodel then
    --     datamodel = datamodelJson
    -- elseif datamodelJson then
    --     datamodel = table.merge(datamodelJson, datamodel)
    -- end

    local rojoProject = rojo:loadRojoProject()
    if rojoProject then
        datamodel = datamodel and table.merge(datamodel, rojoProject) or rojoProject
    end
    if not datamodel then
        return
    end
    for name, members in pairs(datamodel.children) do
        addChild(name, members, self.DataModelChilds, nil, "")
    end
end

function rbxApi:generateLibs(datamodel)
    local api = self:loadApiJson()
    local classNames = self:getClassNames()
    local libs = {
        objects = {},
        globals = {}
    }
    self:loadRojoProject(datamodel)
    for _, rbxClass in pairs(api.Classes) do
        if classNames[rbxClass.Name] then
           libs.objects[rbxClass.Name] = self:getMembers(rbxClass.Members, true, rbxClass.Name)
        end
    end
    for className, superClass in pairs(classNames) do
        self:addSuperMembers(className, superClass, libs.objects)
    end
    for _, rbxDataType in pairs(api.DataTypes) do
        libs.objects[rbxDataType.Name] = self:getMembers(rbxDataType.Members, false, rbxDataType.Name)
    end
    for _, rbxConstructor in pairs(api.Constructors) do
        self.Constructors[rbxConstructor.Name] = true
        libs.globals[rbxConstructor.Name] = self:getMembers(rbxConstructor.Members, false, rbxConstructor.Name)
    end
    return libs
end

return rbxApi