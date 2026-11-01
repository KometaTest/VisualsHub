local CONFIG = {
    ScriptName   = "VisualsHub",
    DisplayName  = "gamesense", -- [v72] название в меню / ватермарке / уведомлениях (папка - ScriptName)
    GameFolder   = tostring(game.GameId),

    UpdateRate   = 0.1,
    BotScanRate  = 0.5,
    HookGrace    = 1.25,
    HitHealth    = 60,

    Teams = {
        Survivors = "Survivors",
        Killer    = "Killer",
        Spectator = "Spectator",
    },

    ObjectFillTransparency    = 0.65,
    ObjectOutlineTransparency = 0.15,

    -- Лимит Roblox на одновременно отрисованные Highlight ~31 (берём с запасом).
    -- [CHANGED v3] статичные объекты занимают по 1 Highlight на тип, остальное - игрокам/зомби.
    MaxHighlights = 30,

    TagFont = Enum.Font.GothamBold,

    HUDTop = 120,
    ChaseScreenY = 1 - 2 / 6, -- ChasePreview: 2/6 экрана снизу вверх

    -- Veil (значения из описания способностей в игре)
    Veil = {
        MaxSpears       = 2,   -- копий максимум
        SpearRecharge   = 15,  -- сек на восстановление одного копья
        AbilityCooldown = 45,  -- сек кулдауна "Through the Veil" после броска
    },

    -- Masked: "Mask Up" - смена маски каждые 30 сек
    Masked = {
        SwapCooldown = 30,
    },

    -- Hidden (из Powers: Leap = ability2, Mark/M2 = ability1)
    Hidden = {
        LeapCooldown = 25,
        MarkCooldown = 17,
    },

    -- [NEW] Butcher (из save.rbxmx -> LocalScript "Animations" = Powers Butcher'а)
    Butcher = {
        MaxTraps      = 2,   -- Beartraps по умолчанию 2, очередь сбрасывается при Beartraps >= 2
        TrapRecharge  = 45,  -- runQueuedCooldowns: TweenInfo.new(45) на каждый потраченный капкан
        TrapPlaceTime = 2.5, -- startPlacing: TrapPlacementEndsAt = clock + 2.5
    },

    -- [NEW] Slasher (ремоуты Remotes.Killers.Jason; save.rbxmx 2 -> LocalScript Powers)
    Slasher = {
        MistDuration    = 13, -- LakeMist: авто-снятие невидимости через 13с
        MistCooldown    = 30, -- после снятия невидимости
        PursuitDuration = 22, -- Pursuit: task.delay(22, ...)
        PursuitCooldown = 60, -- после конца Pursuit
    },

    GenBarRefDistance = 55,
    GenBarMinScale    = 0.6,
    GenBarMaxScale    = 1.15,
}

local GENV = (getgenv and getgenv()) or _G
if type(GENV.__VisualsHubUnload) == "function" then
    pcall(GENV.__VisualsHubUnload)
end

-- ИЗМЕНЕНО (только GUI): вместо Obsidian (loadstring с GitHub) - встроенная NeverUI ниже.
