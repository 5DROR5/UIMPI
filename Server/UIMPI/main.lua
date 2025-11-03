print("[UIMPI] Performance Limiter v1.1")

local MAX_PERFORMANCE_RATING = 120
local playerPerformanceData = {}
local playerViolations = {}
local playerReadyStatus = {}
local playerLastWarnedRating = {}
local activePlayerCount = 0

local function SetMaxPerformanceRating(newLimit)
    MAX_PERFORMANCE_RATING = newLimit
    print("[UIMPI] Limit changed to: " .. newLimit)
    
    local limitStr = tostring(MAX_PERFORMANCE_RATING)
    for playerID, isReady in pairs(playerReadyStatus) do
        if isReady then
            MP.TriggerClientEvent(playerID, "PerfModReceiveLimit", limitStr)
            MP.SendChatMessage(playerID, "Limit changed to: " .. newLimit)
        end
    end
end

function onPlayerJoin(playerID)
    print("[UIMPI] Player " .. playerID .. " joined")
    
    playerPerformanceData[playerID] = 0
    playerViolations[playerID] = 0
    playerReadyStatus[playerID] = true
    playerLastWarnedRating[playerID] = nil
    activePlayerCount = activePlayerCount + 1
    
    MP.TriggerClientEvent(playerID, "PerfModReceiveLimit", tostring(MAX_PERFORMANCE_RATING))
    
    local msg = string.format(
        "This server is limited to a Performance Rating of %d. You can see your car's rating in the UIMPI app.",
        MAX_PERFORMANCE_RATING
    )
    MP.SendChatMessage(playerID, msg)
end

function onPlayerDisconnect(playerID)
    print("[UIMPI] Player " .. playerID .. " disconnected")
    
    if playerPerformanceData[playerID] then
        activePlayerCount = activePlayerCount - 1
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
    
    local isVehicleAllowed = (currentRating <= MAX_PERFORMANCE_RATING)
    
    if not isVehicleAllowed then
        if playerLastWarnedRating[playerID] ~= currentRating then
            print("[UIMPI] DENIED - Player: " .. playerID .. " | Rating: " .. currentRating .. " | Limit: " .. MAX_PERFORMANCE_RATING)
            
            playerViolations[playerID] = (playerViolations[playerID] or 0) + 1
            
            local msg = string.format(
                "Limit: %d - Your car: %d - DENIED! Vehicle frozen.", 
                MAX_PERFORMANCE_RATING, 
                currentRating
            )
            MP.SendChatMessage(playerID, msg)
            playerLastWarnedRating[playerID] = currentRating
        end
        
        MP.TriggerClientEvent(playerID, "PerfModFreezeVehicle", "")
    else
        if playerLastWarnedRating[playerID] then
            MP.SendChatMessage(playerID, "Your vehicle is now within the limit. Unfrozen.")
            playerLastWarnedRating[playerID] = nil
        end
    
        playerViolations[playerID] = 0
        MP.TriggerClientEvent(playerID, "PerfModUnfreezeVehicle", "")
    end
end

function onRequestLimit(playerID, data)
    MP.TriggerClientEvent(playerID, "PerfModReceiveLimit", tostring(MAX_PERFORMANCE_RATING))
end

MP.RegisterEvent("onPlayerJoin", "onPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect", "onPlayerDisconnect")
MP.RegisterEvent("PerfModCheckVehicle", "onVehicleDataReceived")
MP.RegisterEvent("PerfModRequestLimit", "onRequestLimit")

print("[UIMPI] Server loaded - Limit: " .. MAX_PERFORMANCE_RATING)
