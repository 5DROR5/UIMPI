-- =============================================================================
-- Performance Limiter - Server-Side
-- License: The Unlicense (https://unlicense.org)
-- This is free and unencumbered software released into the public domain.
-- =============================================================================

local ROOT = "Resources/Server/UIMPI"

-- =============================================================================
-- STATE
-- =============================================================================
local CONFIG = {}

local MAX_PERFORMANCE_RATING = 122
local DISPLAY_OFFSET         = 2
local VOTE_ENABLED           = false
local VOTE_DURATION          = 20
local VOTE_OPTIONS           = {80, 100, 120, 150, 200, 250}
local ADMIN_NAMES            = {}

local playerPerformanceData  = {}
local playerViolations       = {}
local playerReadyStatus      = {}
local playerLastWarnedRating = {}
local playerLang             = {}
local activePlayerCount      = 0

local voteInProgress  = false
local voteCounts      = {}
local votedPlayers    = {}
local voteStarterName = ""
local voteStartTime   = 0

-- =============================================================================
-- CONFIG LOADING
-- =============================================================================
local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function decodeJSON(str)
    if type(str) ~= "string" then return nil end
    if type(Util) == "table" and Util.JsonDecode then
        local ok, t = pcall(Util.JsonDecode, str)
        if ok and type(t) == "table" then return t end
    end
    return nil
end

local function loadConfig()
    local path = ROOT .. "/config.json"
    local s = readFile(path)
    if not s then
        print("[PerformanceLimiter] config.json not found, using defaults")
        return
    end
    local cfg = decodeJSON(s)
    if not cfg then
        print("[PerformanceLimiter] Failed to parse config.json, using defaults")
        return
    end
    CONFIG = cfg

    if cfg.max_performance_rating then MAX_PERFORMANCE_RATING = cfg.max_performance_rating end
    if cfg.display_offset          then DISPLAY_OFFSET         = cfg.display_offset          end
    if cfg.vote_enabled  ~= nil    then VOTE_ENABLED           = cfg.vote_enabled             end
    if cfg.vote_duration           then VOTE_DURATION          = cfg.vote_duration            end
    if cfg.vote_options            then VOTE_OPTIONS           = cfg.vote_options             end

    if type(cfg.admins) == "table" then
        for _, name in ipairs(cfg.admins) do
            ADMIN_NAMES[name] = true
        end
    end

    print("[PerformanceLimiter] Config loaded - vote_enabled: " .. tostring(VOTE_ENABLED))
end

-- =============================================================================
-- LANGUAGE & TRANSLATIONS
-- =============================================================================
local BEAMNG_LOCALE_MAP = {
    ["he"]      = "he",      ["he-IL"]  = "he",
    ["en"]      = "en",      ["en-US"]  = "en",      ["en-GB"]  = "en",
    ["ar"]      = "ar",      ["ar-SA"]  = "ar",      ["ar-EG"]  = "ar",
    ["de"]      = "de",      ["de-DE"]  = "de",      ["de-AT"]  = "de",      ["de-CH"] = "de",
    ["it"]      = "it",      ["it-IT"]  = "it",
    ["fr"]      = "fr",      ["fr-FR"]  = "fr",      ["fr-BE"]  = "fr",      ["fr-CH"] = "fr",
    ["es"]      = "es",      ["es-ES"]  = "es",      ["es-MX"]  = "es",
    ["ru"]      = "ru",      ["ru-RU"]  = "ru",
    ["cs"]      = "cs",      ["cs-CZ"]  = "cs",
    ["hu"]      = "hu",      ["hu-HU"]  = "hu",
    ["ja"]      = "ja_JP",   ["ja-JP"]  = "ja_JP",
    ["pl"]      = "pl_PL",   ["pl-PL"]  = "pl_PL",
    ["pt-BR"]   = "pt_BR",
    ["pt"]      = "pt_PT",   ["pt-PT"]  = "pt_PT",
    ["sv"]      = "sv_SE",   ["sv-SE"]  = "sv_SE",
    ["tr"]      = "tr_TR",   ["tr-TR"]  = "tr_TR",
    ["uk"]      = "uk",      ["uk-UA"]  = "uk",
    ["zh"]      = "zh_Hans", ["zh-CN"]  = "zh_Hans", ["zh-Hans"] = "zh_Hans",
}

local function resolveBeamNGLocale(beamng_lang)
    if not beamng_lang or beamng_lang == "" then return nil end
    local mapped = BEAMNG_LOCALE_MAP[beamng_lang]
    if mapped then return mapped end
    local prefix = beamng_lang:match("^([a-zA-Z]+)")
    return prefix and BEAMNG_LOCALE_MAP[prefix:lower()]
end

local translations = {}

local function loadTranslations()
    local langs = { "he", "en", "ar", "de", "it", "fr", "es", "ru", "cs", "hu", "ja_JP", "pl_PL", "pt_BR", "pt_PT", "sv_SE", "tr_TR", "uk", "zh_Hans" }
    local count = 0
    for _, code in ipairs(langs) do
        local path = ROOT .. "/lang/" .. code .. ".json"
        local raw  = readFile(path)
        translations[code] = raw and (decodeJSON(raw) or {}) or {}
        if raw then count = count + 1 end
    end
    print("[PerformanceLimiter] Translations loaded for " .. count .. " languages")
end

local function translate(lang, key, vars)
    local text = (translations[lang] or {})[key] or (translations["en"] or {})[key] or key
    if vars then
        for k, v in pairs(vars) do
            text = text:gsub("${" .. k .. "}", tostring(v))
        end
    end
    return text
end

local function translateForPlayer(pid, key, vars)
    local lang = (pid == -1) and "en" or (playerLang[pid] or "en")
    return translate(lang, key, vars)
end

local function broadcastTranslated(key, vars)
    for pid, isReady in pairs(playerReadyStatus) do
        if isReady then
            MP.SendChatMessage(pid, translateForPlayer(pid, key, vars))
        end
    end
end

-- Sends only the keys needed by the client UI
local CLIENT_KEYS = {
    "banner_limit", "banner_over", "banner_tip",
    "vote_title", "vote_votes", "vote_you_voted", "vote_click_to_vote"
}
local function sendTranslationsToClient(playerID)
    local lang  = playerLang[playerID] or "en"
    local t     = translations[lang]   or translations["en"] or {}
    local parts = { string.format('"lang":"%s"', lang) }
    for _, k in ipairs(CLIENT_KEYS) do
        local v = (t[k] or ""):gsub('\\', '\\\\'):gsub('"', '\\"')
        parts[#parts + 1] = string.format('"%s":"%s"', k, v)
    end
    MP.TriggerClientEvent(playerID, "PerfModTranslations", "{" .. table.concat(parts, ",") .. "}")
end

-- =============================================================================
-- UTILITIES
-- =============================================================================
local function getDisplayLimit()
    return MAX_PERFORMANCE_RATING - DISPLAY_OFFSET
end

local function isAdmin(pid)
    if pid == -1 then return true end
    if not MP.GetPlayerName then return false end
    local name = MP.GetPlayerName(pid) or ""
    return ADMIN_NAMES[name] == true
end

local function broadcastToReady(event, payload)
    for pid, isReady in pairs(playerReadyStatus) do
        if isReady then MP.TriggerClientEvent(pid, event, payload) end
    end
end

-- =============================================================================
-- PLAYER RATINGS
-- =============================================================================
local function broadcastPlayerRating(playerID)
    local rating = playerPerformanceData[playerID]
    if not rating then return end
    local playerName = MP.GetPlayerName(playerID)
    if not playerName then return end
    local payload = string.format('{"playerName":"%s","rating":%d,"pid":%d}',
        playerName, rating, playerID)
    for pid, isReady in pairs(playerReadyStatus) do
        if isReady then
            MP.TriggerClientEvent(pid, "updatePlayerPerformanceRating", payload)
        end
    end
end

local function SetMaxPerformanceRating(newLimit)
    MAX_PERFORMANCE_RATING = newLimit
    local displayLimit = getDisplayLimit()
    for playerID, isReady in pairs(playerReadyStatus) do
        if isReady then
            MP.TriggerClientEvent(playerID, "PerfModReceiveLimit", tostring(displayLimit))
            MP.SendChatMessage(playerID, translateForPlayer(playerID, "perf_limit_changed", {limit = displayLimit}))
        end
    end
end

-- =============================================================================
-- VOTE SYSTEM
-- =============================================================================
local function broadcastVoteResults()
    local resultsArray = "["
    local first = true
    for _, option in ipairs(VOTE_OPTIONS) do
        if not first then resultsArray = resultsArray .. "," end
        local count = voteCounts[option] or 0
        resultsArray = resultsArray .. string.format('{"option":%d,"votes":%d}', option, count)
        first = false
    end
    resultsArray = resultsArray .. "]"
    broadcastToReady("PerfModVoteUpdate", resultsArray)
end

local function endVote(forced)
    if not voteInProgress then return end
    local winningOption = MAX_PERFORMANCE_RATING
    local maxVotes   = 0
    local totalVotes = 0
    for option, count in pairs(voteCounts) do
        totalVotes = totalVotes + count
        if count > maxVotes then
            maxVotes = count
            winningOption = option
        elseif count == maxVotes and option < winningOption then
            winningOption = option
        end
    end
    voteInProgress = false
    if totalVotes > 0 then
        SetMaxPerformanceRating(winningOption)
        local displayLimit = getDisplayLimit()
        broadcastTranslated("vote_separator")
        broadcastTranslated("vote_ended_new_limit",  {limit   = displayLimit})
        broadcastTranslated("vote_ended_stats",      {total   = totalVotes, winning = maxVotes})
        broadcastTranslated("vote_separator")
    else
        broadcastTranslated("vote_ended_no_votes")
    end
    local endData = string.format('{"winner":%d,"totalVotes":%d,"forced":%s}',
        winningOption, totalVotes, tostring(forced or false))
    broadcastToReady("PerfModVoteEnded", endData)
end

local function startVote(playerID)
    if not isAdmin(playerID) then
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "vote_only_admins_start"))
        return
    end
    if voteInProgress then
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "vote_already_in_progress"))
        return
    end
    voteInProgress  = true
    voteCounts      = {}
    votedPlayers    = {}
    voteStartTime   = os.time()
    voteStarterName = MP.GetPlayerName(playerID)
    for _, option in ipairs(VOTE_OPTIONS) do voteCounts[option] = 0 end
    broadcastTranslated("vote_started_broadcast", {name     = voteStarterName})
    broadcastTranslated("vote_time_announcement", {duration = VOTE_DURATION})
    broadcastTranslated("vote_use_ui")
    local optionsStr = table.concat(VOTE_OPTIONS, ",")
    local voteData = string.format('{"options":[%s],"duration":%d,"starter":"%s"}',
        optionsStr, VOTE_DURATION, voteStarterName)
    broadcastToReady("PerfModVoteStarted", voteData)
end

function onPlayerVote(playerID, voteOption)
    if not voteInProgress then
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "vote_no_in_progress"))
        return
    end
    local option = tonumber(voteOption)
    local validOption = false
    for _, opt in ipairs(VOTE_OPTIONS) do
        if opt == option then validOption = true break end
    end
    if not validOption then
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "vote_invalid_option", {options = table.concat(VOTE_OPTIONS, ", ")}))
        return
    end
    if votedPlayers[playerID] then
        local oldVote = votedPlayers[playerID]
        voteCounts[oldVote] = (voteCounts[oldVote] or 1) - 1
    end
    voteCounts[option] = (voteCounts[option] or 0) + 1
    votedPlayers[playerID] = option
    MP.SendChatMessage(playerID, translateForPlayer(playerID, "vote_cast", {option = option}))
    broadcastVoteResults()
end

function onVoteTimerTick()
    if not voteInProgress then return end
    local elapsed  = os.time() - voteStartTime
    local timeLeft = VOTE_DURATION - elapsed
    if     timeLeft == 10 then broadcastTranslated("vote_timer_10")
    elseif timeLeft == 5  then broadcastTranslated("vote_timer_5")
    elseif timeLeft == 3  then broadcastTranslated("vote_timer_3")
    elseif timeLeft == 1  then broadcastTranslated("vote_timer_1")
    end
    if elapsed >= VOTE_DURATION then endVote(false) end
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================
function onChatMessage(playerID, playerName, message)
    local newLimit = string.match(message, "^/setlimit%s+(%d+)$")
    if newLimit then
        if isAdmin(playerID) then
            SetMaxPerformanceRating(tonumber(newLimit))
            broadcastTranslated("admin_set_limit", {name = playerName, limit = getDisplayLimit()})
        else
            MP.SendChatMessage(playerID, translateForPlayer(playerID, "admin_only_setlimit"))
        end
        return 1
    end

    if VOTE_ENABLED then
        if message == "/startvote" then
            startVote(playerID)
            return 1
        end
        if message == "/endvote" then
            if isAdmin(playerID) then
                if voteInProgress then
                    broadcastTranslated("vote_admin_ended", {name = playerName})
                    endVote(true)
                else
                    MP.SendChatMessage(playerID, translateForPlayer(playerID, "vote_none_in_progress"))
                end
            else
                MP.SendChatMessage(playerID, translateForPlayer(playerID, "vote_only_admins_end"))
            end
            return 1
        end
        local voteValue = string.match(message, "^/vote%s+(%d+)$")
        if voteValue then
            onPlayerVote(playerID, voteValue)
            return 1
        end
    end

    if message == "/limit" then
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "perf_limit_info", {limit = getDisplayLimit()}))
        if VOTE_ENABLED and voteInProgress then
            local timeLeft = VOTE_DURATION - (os.time() - voteStartTime)
            MP.SendChatMessage(playerID, translateForPlayer(playerID, "vote_limit_in_progress", {time = timeLeft}))
        end
        return 1
    end

    if message == "/perfhelp" then
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "perfhelp_title"))
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "perfhelp_description"))
        MP.SendChatMessage(playerID, "")
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "perfhelp_commands_header"))
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "perfhelp_limit_cmd"))
        if VOTE_ENABLED then
            MP.SendChatMessage(playerID, translateForPlayer(playerID, "perfhelp_vote_cmd"))
        end
        if isAdmin(playerID) then
            MP.SendChatMessage(playerID, "")
            MP.SendChatMessage(playerID, translateForPlayer(playerID, "perfhelp_admin_header"))
            if VOTE_ENABLED then
                MP.SendChatMessage(playerID, translateForPlayer(playerID, "perfhelp_startvote_cmd"))
                MP.SendChatMessage(playerID, translateForPlayer(playerID, "perfhelp_endvote_cmd"))
            end
            MP.SendChatMessage(playerID, translateForPlayer(playerID, "perfhelp_setlimit_cmd"))
        end
        MP.SendChatMessage(playerID, "")
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "perfhelp_tips_header"))
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "perfhelp_tips_colors"))
        return 1
    end

    return 0
end

function onPlayerSetLang(playerID, beamng_lang)
    local resolved = resolveBeamNGLocale(beamng_lang) or "en"
    playerLang[playerID] = resolved
    sendTranslationsToClient(playerID)
end

function onPlayerJoin(playerID)
    playerPerformanceData[playerID]  = 0
    playerViolations[playerID]       = 0
    playerReadyStatus[playerID]      = true
    playerLastWarnedRating[playerID] = nil
    playerLang[playerID]             = "en"
    activePlayerCount = activePlayerCount + 1

    MP.TriggerClientEvent(playerID, "PerfModReceiveLimit", tostring(getDisplayLimit()))

    if VOTE_ENABLED and voteInProgress then
        local timeLeft = VOTE_DURATION - (os.time() - voteStartTime)
        MP.SendChatMessage(playerID, translateForPlayer(playerID, "vote_join_in_progress", {time = timeLeft}))
        local optionsStr = table.concat(VOTE_OPTIONS, ",")
        local voteData = string.format('{"options":[%s],"duration":%d,"starter":"%s","elapsed":%.1f}',
            optionsStr, VOTE_DURATION, voteStarterName, os.time() - voteStartTime)
        MP.TriggerClientEvent(playerID, "PerfModVoteStarted", voteData)
        broadcastVoteResults()
    end

    for otherPID, isReady in pairs(playerReadyStatus) do
        if otherPID ~= playerID and isReady then broadcastPlayerRating(otherPID) end
    end
    broadcastPlayerRating(playerID)
end

function onPlayerDisconnect(playerID)
    if playerPerformanceData[playerID] then
        activePlayerCount = activePlayerCount - 1
    end
    if VOTE_ENABLED and voteInProgress and votedPlayers[playerID] then
        local votedFor = votedPlayers[playerID]
        voteCounts[votedFor] = (voteCounts[votedFor] or 1) - 1
        votedPlayers[playerID] = nil
        broadcastVoteResults()
    end
    playerPerformanceData[playerID]  = nil
    playerViolations[playerID]       = nil
    playerReadyStatus[playerID]      = nil
    playerLastWarnedRating[playerID] = nil
    playerLang[playerID]             = nil
end

function onVehicleDataReceived(playerID, data)
    if not data or data == "" or data == "null" then return end
    local currentRating = tonumber(string.match(data, '"rating":(%d+)'))
    if not currentRating then return end
    playerPerformanceData[playerID] = currentRating
    broadcastPlayerRating(playerID)
    if currentRating > MAX_PERFORMANCE_RATING then
        if playerLastWarnedRating[playerID] ~= currentRating then
            playerViolations[playerID] = (playerViolations[playerID] or 0) + 1
            MP.SendChatMessage(playerID, translateForPlayer(playerID, "perf_frozen", {rating = currentRating, limit = getDisplayLimit()}))
            playerLastWarnedRating[playerID] = currentRating
        end
        MP.TriggerClientEvent(playerID, "PerfModFreezeVehicle", "")
    else
        if playerLastWarnedRating[playerID] then
            MP.SendChatMessage(playerID, translateForPlayer(playerID, "perf_unfrozen"))
            playerLastWarnedRating[playerID] = nil
        end
        playerViolations[playerID] = 0
        MP.TriggerClientEvent(playerID, "PerfModUnfreezeVehicle", "")
    end
end

function onRequestLimit(playerID, _)
    MP.TriggerClientEvent(playerID, "PerfModReceiveLimit", tostring(getDisplayLimit()))
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================
loadConfig()
loadTranslations()

MP.RegisterEvent("onPlayerJoin",        "onPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect",  "onPlayerDisconnect")
MP.RegisterEvent("PerfModCheckVehicle", "onVehicleDataReceived")
MP.RegisterEvent("PerfModRequestLimit", "onRequestLimit")
MP.RegisterEvent("onChatMessage",       "onChatMessage")
MP.RegisterEvent("PerfModSetLang",      "onPlayerSetLang")

if VOTE_ENABLED then
    MP.RegisterEvent("PerfModPlayerVote", "onPlayerVote")
    MP.CreateEventTimer("VoteTimerTick", 1000)
    MP.RegisterEvent("VoteTimerTick",     "onVoteTimerTick")
end

print("[PerformanceLimiter] Loaded - limit: " .. MAX_PERFORMANCE_RATING)