print("[UIMPI] Performance Limiter v2.0")

local ADMIN_NAMES = { 
    ["PlayerName"] = true
    -- ["PlayerName2"] = true,
    -- ["PlayerName3"] = true
}

local function isAdmin(pid)
    if pid == -1 then return true end
    if not MP.GetPlayerName then return false end
    local name = MP.GetPlayerName(pid) or ""
    return ADMIN_NAMES[name] == true
end

local MAX_PERFORMANCE_RATING = 120
local playerPerformanceData = {}
local playerViolations = {}
local playerReadyStatus = {}
local playerLastWarnedRating = {}
local activePlayerCount = 0

local voteInProgress = false
local voteOptions = {80, 100, 120, 150, 200, 250}
local voteCounts = {}
local votedPlayers = {}
local voteTimer = 0
local VOTE_DURATION = 20
local voteStarterName = ""
local voteStartTime = 0

local function broadcastPlayerRating(playerID)
    local rating = playerPerformanceData[playerID]
    if not rating then return end

    local playerName = MP.GetPlayerName(playerID)
    if not playerName then return end

    for pid, isReady in pairs(playerReadyStatus) do
        if isReady then
            local payload = string.format('{"playerName":"%s","rating":%d,"pid":%d}',
                playerName, rating, playerID)
            MP.TriggerClientEvent(pid, "updatePlayerPerformanceRating", payload)
        end
    end
end

local function SetMaxPerformanceRating(newLimit)
    MAX_PERFORMANCE_RATING = newLimit
    
    local limitStr = tostring(MAX_PERFORMANCE_RATING)
    for playerID, isReady in pairs(playerReadyStatus) do
        if isReady then
            MP.TriggerClientEvent(playerID, "PerfModReceiveLimit", limitStr)
            MP.SendChatMessage(playerID, "Performance limit changed to: " .. newLimit)
        end
    end
end

local function broadcastVoteResults()
    local resultsArray = "["
    local first = true
    
    for _, option in ipairs(voteOptions) do
        if not first then resultsArray = resultsArray .. "," end
        local count = voteCounts[option] or 0
        resultsArray = resultsArray .. string.format('{"option":%d,"votes":%d}', option, count)
        first = false
    end
    resultsArray = resultsArray .. "]"
    
    for pid, isReady in pairs(playerReadyStatus) do
        if isReady then
            MP.TriggerClientEvent(pid, "PerfModVoteUpdate", resultsArray)
        end
    end
end

local function endVote(forced)
    if not voteInProgress then return end
    
    local winningOption = MAX_PERFORMANCE_RATING
    local maxVotes = 0
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
        MP.SendChatMessage(-1, "━━━━━━━━━━━━━━━━━━━━━━━━━━")
        MP.SendChatMessage(-1, string.format("[VOTE] Vote ended! New limit: %d", winningOption))
        MP.SendChatMessage(-1, string.format("[VOTE] Total votes: %d | Winning votes: %d", totalVotes, maxVotes))
        MP.SendChatMessage(-1, "━━━━━━━━━━━━━━━━━━━━━━━━━━")
    else
        MP.SendChatMessage(-1, "[VOTE] Vote ended with no votes - limit unchanged")
    end
    
    local endData = string.format('{"winner":%d,"totalVotes":%d,"forced":%s}', 
        winningOption, totalVotes, tostring(forced or false))
    for pid, isReady in pairs(playerReadyStatus) do
        if isReady then
            MP.TriggerClientEvent(pid, "PerfModVoteEnded", endData)
        end
    end
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
    
    voteInProgress = true
    voteCounts = {}
    votedPlayers = {}
    voteTimer = 0
    voteStartTime = os.time()
    voteStarterName = MP.GetPlayerName(playerID)
    
    for _, option in ipairs(voteOptions) do
        voteCounts[option] = 0
    end
    
    MP.SendChatMessage(-1, string.format("[VOTE] %s started a performance limit vote!", voteStarterName))
    MP.SendChatMessage(-1, "[VOTE] You have " .. VOTE_DURATION .. " seconds to vote!")
    MP.SendChatMessage(-1, "[VOTE] Use the UI or type /vote [value]")
    
    local optionsStr = table.concat(voteOptions, ",")
    for pid, isReady in pairs(playerReadyStatus) do
        if isReady then
            local voteData = string.format('{"options":[%s],"duration":%d,"starter":"%s"}', 
                optionsStr, VOTE_DURATION, voteStarterName)
            MP.TriggerClientEvent(pid, "PerfModVoteStarted", voteData)
        end
    end
end

function onPlayerVote(playerID, voteOption)
    if not voteInProgress then
        MP.SendChatMessage(playerID, "No vote is currently in progress")
        return
    end
    
    local option = tonumber(voteOption)
    
    local validOption = false
    for _, opt in ipairs(voteOptions) do
        if opt == option then
            validOption = true
            break
        end
    end
    
    if not validOption then
        MP.SendChatMessage(playerID, "Invalid vote option. Available: " .. table.concat(voteOptions, ", "))
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

function onChatMessage(playerID, playerName, message)
    local newLimit = string.match(message, "^/setlimit%s+(%d+)$")
    if newLimit then
        if isAdmin(playerID) then
            SetMaxPerformanceRating(tonumber(newLimit))
            MP.SendChatMessage(-1, string.format("[ADMIN] %s set the limit to %d", playerName, tonumber(newLimit)))
            return 1
        else
            MP.SendChatMessage(playerID, "❌ Only admins can use /setlimit")
            return 1
        end
    end
    
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
    
    if message == "/limit" then
        MP.SendChatMessage(playerID, "Current performance limit: " .. MAX_PERFORMANCE_RATING)
        if voteInProgress then
            local timeLeft = math.ceil(VOTE_DURATION - voteTimer)
            MP.SendChatMessage(playerID, string.format("Vote in progress! %d seconds left", timeLeft))
        end
        return 1
    end
    
    if message == "/perfhelp" then
        MP.SendChatMessage(playerID, "━━━ Performance Limiter Commands ━━━")
        MP.SendChatMessage(playerID, "/limit - Show current limit")
        MP.SendChatMessage(playerID, "/vote [value] - Vote for a limit")
        if isAdmin(playerID) then
            MP.SendChatMessage(playerID, "/startvote - Start a vote (admin)")
            MP.SendChatMessage(playerID, "/endvote - End vote early (admin)")
            MP.SendChatMessage(playerID, "/setlimit [value] - Set limit instantly (admin)")
        end
        return 1
    end
    
    return 0
end

function onPlayerJoin(playerID)
    playerPerformanceData[playerID] = 0
    playerViolations[playerID] = 0
    playerReadyStatus[playerID] = true
    playerLastWarnedRating[playerID] = nil
    activePlayerCount = activePlayerCount + 1

    MP.TriggerClientEvent(playerID, "PerfModReceiveLimit", tostring(MAX_PERFORMANCE_RATING))

    local msg = string.format(
        "This server has a Performance Rating limit of %d. Check the UIMPI app to see your rating!",
        MAX_PERFORMANCE_RATING
    )
    MP.SendChatMessage(playerID, msg)
    MP.SendChatMessage(playerID, "Type /perfhelp for commands")

    if voteInProgress then
        local timeLeft = math.ceil(VOTE_DURATION - voteTimer)
        MP.SendChatMessage(playerID, string.format("[VOTE] A vote is in progress! %d seconds left", timeLeft))
        
        local optionsStr = table.concat(voteOptions, ",")
        local voteData = string.format('{"options":[%s],"duration":%d,"starter":"%s","elapsed":%.1f}', 
            optionsStr, VOTE_DURATION, voteStarterName, voteTimer)
        MP.TriggerClientEvent(playerID, "PerfModVoteStarted", voteData)
        
        broadcastVoteResults()
    end

    for otherPID, isReady in pairs(playerReadyStatus) do
        if otherPID ~= playerID and isReady then
            broadcastPlayerRating(otherPID)
        end
    end

    broadcastPlayerRating(playerID)
end

function onPlayerDisconnect(playerID)
    if playerPerformanceData[playerID] then
        activePlayerCount = activePlayerCount - 1
    end
    
    if voteInProgress and votedPlayers[playerID] then
        local votedFor = votedPlayers[playerID]
        voteCounts[votedFor] = (voteCounts[votedFor] or 1) - 1
        votedPlayers[playerID] = nil
        broadcastVoteResults()
    end

    playerPerformanceData[playerID] = nil
    playerViolations[playerID] = nil
    playerReadyStatus[playerID] = nil
    playerLastWarnedRating[playerID] = nil
end

function onVehicleDataReceived(playerID, data)
    if not data or data == "" or data == "null" then return end

    local currentRating = tonumber(string.match(data, '"rating":(%d+)'))

    if not currentRating then return end

    playerPerformanceData[playerID] = currentRating

    broadcastPlayerRating(playerID)

    local isVehicleAllowed = (currentRating <= MAX_PERFORMANCE_RATING)

    if not isVehicleAllowed then
        if playerLastWarnedRating[playerID] ~= currentRating then
            playerViolations[playerID] = (playerViolations[playerID] or 0) + 1

            local msg = string.format(
                "❌ Limit: %d | Your car: %d | DENIED! Vehicle frozen.",
                MAX_PERFORMANCE_RATING,
                currentRating
            )
            MP.SendChatMessage(playerID, msg)
            playerLastWarnedRating[playerID] = currentRating
        end

        MP.TriggerClientEvent(playerID, "PerfModFreezeVehicle", "")
    else
        if playerLastWarnedRating[playerID] then
            MP.SendChatMessage(playerID, "✓ Your vehicle is now within the limit. Unfrozen!")
            playerLastWarnedRating[playerID] = nil
        end

        playerViolations[playerID] = 0
        MP.TriggerClientEvent(playerID, "PerfModUnfreezeVehicle", "")
    end
end

function onRequestLimit(playerID, data)
    MP.TriggerClientEvent(playerID, "PerfModReceiveLimit", tostring(MAX_PERFORMANCE_RATING))
end

local lastVoteLog = 0
function onVoteTimerTick()
    if not voteInProgress then return end
    
    local currentTime = os.time()
    local elapsed = currentTime - voteStartTime
    
    local timeLeft = VOTE_DURATION - elapsed
    if timeLeft == 10 then
        MP.SendChatMessage(-1, "[VOTE] 10 seconds left to vote!")
    elseif timeLeft == 5 then
        MP.SendChatMessage(-1, "[VOTE] 5 seconds left!")
    elseif timeLeft == 3 then
        MP.SendChatMessage(-1, "[VOTE] 3 seconds!")
    elseif timeLeft == 1 then
        MP.SendChatMessage(-1, "[VOTE] 1 second!")
    end
    
    if elapsed >= VOTE_DURATION then
        lastVoteLog = 0
        endVote(false)
    end
end

MP.RegisterEvent("onPlayerJoin", "onPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect", "onPlayerDisconnect")
MP.RegisterEvent("PerfModCheckVehicle", "onVehicleDataReceived")
MP.RegisterEvent("PerfModRequestLimit", "onRequestLimit")
MP.RegisterEvent("onChatMessage", "onChatMessage")
MP.RegisterEvent("PerfModPlayerVote", "onPlayerVote")

MP.CreateEventTimer("VoteTimerTick", 1000)
MP.RegisterEvent("VoteTimerTick", "onVoteTimerTick")

print("[UIMPI] Server loaded - Limit: " .. MAX_PERFORMANCE_RATING)
