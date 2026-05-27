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
            MP.SendChatMessage(playerID, "Performance limit changed to: " .. displayLimit)
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
    local maxVotes  = 0
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
        MP.SendChatMessage(-1, "━━━━━━━━━━━━━━━━━━━━━━━━━━")
        MP.SendChatMessage(-1, string.format("[VOTE] Vote ended! New limit: %d", displayLimit))
        MP.SendChatMessage(-1, string.format("[VOTE] Total votes: %d | Winning votes: %d", totalVotes, maxVotes))
        MP.SendChatMessage(-1, "━━━━━━━━━━━━━━━━━━━━━━━━━━")
    else
        MP.SendChatMessage(-1, "[VOTE] Vote ended with no votes - limit unchanged")
    end
    local endData = string.format('{"winner":%d,"totalVotes":%d,"forced":%s}',
        winningOption, totalVotes, tostring(forced or false))
    broadcastToReady("PerfModVoteEnded", endData)
end

local function startVote(playerID)
    if not isAdmin(playerID) then
        MP.SendChatMessage(playerID, "Only admins can start a vote")
        return
    end
    if voteInProgress then
        MP.SendChatMessage(playerID, "A vote is already in progress!")
        return
    end
    voteInProgress  = true
    voteCounts      = {}
    votedPlayers    = {}
    voteStartTime   = os.time()
    voteStarterName = MP.GetPlayerName(playerID)
    for _, option in ipairs(VOTE_OPTIONS) do voteCounts[option] = 0 end
    MP.SendChatMessage(-1, string.format("[VOTE] %s started a performance limit vote!", voteStarterName))
    MP.SendChatMessage(-1, "[VOTE] You have " .. VOTE_DURATION .. " seconds to vote!")
    MP.SendChatMessage(-1, "[VOTE] Use the UI or type /vote [value]")
    local optionsStr = table.concat(VOTE_OPTIONS, ",")
    local voteData = string.format('{"options":[%s],"duration":%d,"starter":"%s"}',
        optionsStr, VOTE_DURATION, voteStarterName)
    broadcastToReady("PerfModVoteStarted", voteData)
end

function onPlayerVote(playerID, voteOption)
    if not voteInProgress then
        MP.SendChatMessage(playerID, "No vote is currently in progress")
        return
    end
    local option = tonumber(voteOption)
    local validOption = false
    for _, opt in ipairs(VOTE_OPTIONS) do
        if opt == option then validOption = true break end
    end
    if not validOption then
        MP.SendChatMessage(playerID, "Invalid vote option. Available: " .. table.concat(VOTE_OPTIONS, ", "))
        return
    end
    if votedPlayers[playerID] then
        local oldVote = votedPlayers[playerID]
        voteCounts[oldVote] = (voteCounts[oldVote] or 1) - 1
    end
    voteCounts[option] = (voteCounts[option] or 0) + 1
    votedPlayers[playerID] = option
    MP.SendChatMessage(playerID, string.format("✓ You voted for limit: %d", option))
    broadcastVoteResults()
end

function onVoteTimerTick()
    if not voteInProgress then return end
    local elapsed  = os.time() - voteStartTime
    local timeLeft = VOTE_DURATION - elapsed
    if     timeLeft == 10 then MP.SendChatMessage(-1, "[VOTE] 10 seconds left to vote!")
    elseif timeLeft == 5  then MP.SendChatMessage(-1, "[VOTE] 5 seconds left!")
    elseif timeLeft == 3  then MP.SendChatMessage(-1, "[VOTE] 3 seconds!")
    elseif timeLeft == 1  then MP.SendChatMessage(-1, "[VOTE] 1 second!")
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
            MP.SendChatMessage(-1, string.format("[ADMIN] %s set the limit to %d", playerName, getDisplayLimit()))
        else
            MP.SendChatMessage(playerID, "❌ Only admins can use /setlimit")
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
                    MP.SendChatMessage(-1, string.format("[ADMIN] %s ended the vote early", playerName))
                    endVote(true)
                else
                    MP.SendChatMessage(playerID, "No vote is in progress")
                end
            else
                MP.SendChatMessage(playerID, "❌ Only admins can end votes early")
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
        MP.SendChatMessage(playerID, string.format(
            "📊 Current server limit: %d (cars above this will be frozen)", getDisplayLimit()))
        if VOTE_ENABLED and voteInProgress then
            local timeLeft = VOTE_DURATION - (os.time() - voteStartTime)
            MP.SendChatMessage(playerID, string.format("🗳️ Vote in progress! %d seconds left to vote", timeLeft))
        end
        return 1
    end

    if message == "/perfhelp" then
        MP.SendChatMessage(playerID, "━━━ 🏁 Performance Limiter Help ━━━")
        MP.SendChatMessage(playerID, "This server limits car ratings to keep racing fair")
        MP.SendChatMessage(playerID, "")
        MP.SendChatMessage(playerID, "📋 Commands:")
        MP.SendChatMessage(playerID, "/limit - Show current server limit")
        if VOTE_ENABLED then
            MP.SendChatMessage(playerID, "/vote [number] - Vote to change the limit")
        end
        if isAdmin(playerID) then
            MP.SendChatMessage(playerID, "")
            MP.SendChatMessage(playerID, "👑 Admin Commands:")
            if VOTE_ENABLED then
                MP.SendChatMessage(playerID, "/startvote - Start a community vote")
                MP.SendChatMessage(playerID, "/endvote - End vote early")
            end
            MP.SendChatMessage(playerID, "/setlimit [number] - Change limit instantly")
        end
        MP.SendChatMessage(playerID, "")
        MP.SendChatMessage(playerID, "💡 Check the colored values in the app:")
        MP.SendChatMessage(playerID, "🔴 Red = maxed out | 🟠 Orange = medium | 🟢 Green = can improve")
        return 1
    end

    return 0
end

function onPlayerJoin(playerID)
    playerPerformanceData[playerID]  = 0
    playerViolations[playerID]       = 0
    playerReadyStatus[playerID]      = true
    playerLastWarnedRating[playerID] = nil
    activePlayerCount = activePlayerCount + 1

    MP.TriggerClientEvent(playerID, "PerfModReceiveLimit", tostring(getDisplayLimit()))

    if VOTE_ENABLED and voteInProgress then
        local timeLeft = VOTE_DURATION - (os.time() - voteStartTime)
        MP.SendChatMessage(playerID, string.format("[VOTE] A vote is in progress! %d seconds left", timeLeft))
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
            MP.SendChatMessage(playerID, string.format(
                "❌ Your car (%d) exceeds server limit (%d) 🔒 FROZEN - Please spawn a different vehicle",
                currentRating, getDisplayLimit()))
            playerLastWarnedRating[playerID] = currentRating
        end
        MP.TriggerClientEvent(playerID, "PerfModFreezeVehicle", "")
    else
        if playerLastWarnedRating[playerID] then
            MP.SendChatMessage(playerID, "✅ Perfect! Your car is within the limit!")
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

MP.RegisterEvent("onPlayerJoin",        "onPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect",  "onPlayerDisconnect")
MP.RegisterEvent("PerfModCheckVehicle", "onVehicleDataReceived")
MP.RegisterEvent("PerfModRequestLimit", "onRequestLimit")
MP.RegisterEvent("onChatMessage",       "onChatMessage")

if VOTE_ENABLED then
    MP.RegisterEvent("PerfModPlayerVote", "onPlayerVote")
    MP.CreateEventTimer("VoteTimerTick", 1000)
    MP.RegisterEvent("VoteTimerTick", "onVoteTimerTick")
end

print("[PerformanceLimiter] Loaded - limit: " .. MAX_PERFORMANCE_RATING)
