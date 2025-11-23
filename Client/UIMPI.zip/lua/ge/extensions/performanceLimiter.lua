local M = {}

local playerRatings = {}

local function updatePlayerRatingSuffix(playerName, rating)
    if type(MPVehicleGE) == "table" and type(MPVehicleGE.setPlayerNickSuffix) == "function" then
        local suffix = string.format("[%d]", rating)
        MPVehicleGE.setPlayerNickSuffix(playerName, "performance_rating_suffix", suffix)
        print(string.format("[UIMPI] Set rating suffix for '%s': %s", playerName, suffix))
    end
end

local function onReceivePlayerRating(payload)
    if not payload or payload == "" then return end

    local playerName, rating, pid

    if type(payload) == "string" then
        playerName = string.match(payload, '"playerName":"([^"]+)"')
        rating = tonumber(string.match(payload, '"rating":(%d+)'))
        pid = tonumber(string.match(payload, '"pid":(%d+)'))
    end

    if not playerName or not rating then
        print("[UIMPI] Failed to parse rating payload: " .. tostring(payload))
        return
    end

    print(string.format("[UIMPI] Received rating for '%s' (PID: %s): %d", playerName, tostring(pid), rating))

    playerRatings[playerName] = rating

    updatePlayerRatingSuffix(playerName, rating)
end

local function try_register_rating_events()
    if M.registered_rating_events then return end
    if type(AddEventHandler) == "function" then
        AddEventHandler("updatePlayerPerformanceRating", onReceivePlayerRating)
        M.registered_rating_events = true
        print("[UIMPI] Registered rating event handlers")
    end
end

local original_try_register = try_register
try_register = function()
    original_try_register()
    try_register_rating_events()
end

local original_onUpdate = M.onUpdate
M.onUpdate = function(dt)
    if not M.registered_rating_events then
        try_register_rating_events()
    end
    original_onUpdate(dt)
end

try_register_rating_events()

local serverLimit = 999
local frozen = false
local lastVehicleID = nil

local vdata = {
    hp=0,
    torqueNm=0,
    weight=0,
    perfPower=0,
    perfTorque=0,
    brakeTorque=0,
    avgFriction=1.0,
    drivetrain="RWD",
    propulsedWheels=2,
    totalWheels=4,
    rating=0,
    class="D",
    ratingRounded=0,
    maxRPM=0,
    gearboxType="N/A",
    gearCount=0,
    inductionType="NA",
    serverMaxRating=999,
    isVehicleAllowed=true
}

local lastUpdate = 0
local lastSend = 0
local lastFreezeCheck = 0
local dataCollected = false

local function buildVehicleJSON()
    return string.format(
        '{"rating":%d,"hp":%d,"weight":%d,"class":"%s"}',
        vdata.rating,
        vdata.hp,
        vdata.weight,
        vdata.class
    )
end

local function buildFullJSON()
    return string.format(
        '{"hp":%d,"torqueNm":%d,"weight":%d,"perfPower":%d,"perfTorque":%d,"brakeTorque":%d,"avgFriction":%.2f,"drivetrain":"%s","propulsedWheels":%d,"totalWheels":%d,"rating":%d,"class":"%s","ratingRounded":%d,"maxRPM":%d,"gearboxType":"%s","gearCount":%d,"inductionType":"%s","serverMaxRating":%d,"isVehicleAllowed":%s}',
        vdata.hp,
        vdata.torqueNm,
        vdata.weight,
        vdata.perfPower,
        vdata.perfTorque,
        vdata.brakeTorque,
        vdata.avgFriction,
        vdata.drivetrain,
        vdata.propulsedWheels,
        vdata.totalWheels,
        vdata.rating,
        vdata.class,
        vdata.ratingRounded,
        vdata.maxRPM,
        vdata.gearboxType,
        vdata.gearCount,
        vdata.inductionType,
        vdata.serverMaxRating,
        tostring(vdata.isVehicleAllowed)
    )
end

local function calculatePI(vdata, maxLimit)
    local p = tonumber(vdata.perfPower) or 0
    local w = tonumber(vdata.weight) or 0

    local ratingData = {
        rating = 0,
        class = "D",
        ratingRounded = 0,
        isVehicleAllowed = true,
        serverMaxRating = maxLimit
    }

    if p <= 0 or w <= 0 then return ratingData end

    local pwRatio = w / p
    local tqPerTon = (tonumber(vdata.perfTorque) or 0) / (w / 1000)
    local est060 = 0.96 * pwRatio

    local accel = math.max(0, math.min(100, 100 * (1 - math.pow(math.min(est060, 6.80) / 6.80, 0.8))))
    accel = accel * (1 + math.min(0.15, (tqPerTon - 150) / 1000))

    local dtMult = 1.0
    if vdata.drivetrain == "AWD" then
        dtMult = 1.08
    elseif vdata.drivetrain == "FWD" then
        dtMult = 0.97
    end
    accel = math.min(100, accel * dtMult)

    local speed = math.max(0, math.min(100, math.pow((p / w) * 453.6, 0.7) * 15))

    local f = tonumber(vdata.avgFriction) or 1.0
    local grip = 1.0
    if f > 1.5 and f < 2.5 then
        grip = 1.0 + ((f - 1.5) / 1.0) * 0.2
    elseif f >= 2.5 then
        grip = 1.2
    end

    local brake = math.max(0.8, math.min(1.2, 0.7 + ((tonumber(vdata.brakeTorque) or 0) / w / 22.05)))

    local base = (accel * 0.6 + speed * 0.4) * 10
    local final = base * grip * brake

    ratingData.ratingRounded = math.floor(final + 0.5)
    ratingData.rating = math.floor(ratingData.ratingRounded / 4)

    if ratingData.rating < 100 then
        ratingData.class = "D"
    elseif ratingData.rating < 200 then
        ratingData.class = "C"
    elseif ratingData.rating < 300 then
        ratingData.class = "B"
    else
        ratingData.class = "A"
    end

    ratingData.isVehicleAllowed = (ratingData.rating <= maxLimit)

    return ratingData
end

local function updateUI()
    guihooks.trigger('PerformanceLimiterUpdateData', buildFullJSON())
end

local function freeze()
    if frozen then return end
    frozen = true
    local v = be:getPlayerVehicle(0)
    if v then
        core_vehicleBridge.executeAction(v, 'setFreeze', true)
        v:queueLuaCommand('electrics.setIgnitionLevel(0)')
        vdata.isVehicleAllowed = false
        updateUI()
    end
end

local function unfreeze()
    if not frozen then return end
    frozen = false
    local v = be:getPlayerVehicle(0)
    if v then
        core_vehicleBridge.executeAction(v, 'setFreeze', false)
        vdata.isVehicleAllowed = true
        updateUI()
    end
end

local function requestLimit()
    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent('PerfModRequestLimit', '')
    end
end

local function collect()
    local v = be:getPlayerVehicle(0)
    if not v then
        dataCollected = false
        return
    end

    local currentVehicleID = v:getID()
    if currentVehicleID ~= lastVehicleID then
        lastVehicleID = currentVehicleID
        dataCollected = false
    end

    v:queueLuaCommand([[
        local hp, torque, maxRPM, weight = 0, 0, 0, 0
        local propulsed, total = 0, 0
        local drivetrain = "RWD"
        local brakeTorque = 0
        local avgFriction, frictionCount = 0, 0
        local gearboxType, gearCount = "N/A", 0
        local inductionType = "NA"

        local engines = powertrain.getDevicesByCategory("engine")
        if engines and engines[1] then
            hp = engines[1].maxPower * 0.986
            torque = engines[1].maxTorque
            maxRPM = engines[1].maxRPM
        end

        weight = obj:calcBeamStats().total_weight

        if wheels and wheels.wheels then
            for _, w in pairs(wheels.wheels) do
                total = total + 1
                if w.isPropulsed then propulsed = propulsed + 1 end
            end

            if propulsed > 0 and total > 0 then
                if propulsed >= total then
                    drivetrain = "AWD"
                elseif total <= 4 and total > 1 then
                    local ref = v.data.nodes[v.data.refNodes[0].ref].pos
                    local back = v.data.nodes[v.data.refNodes[0].back].pos
                    local vectorForward = vec3(ref) - vec3(back)
                    
                    local avgWheelPos = vec3(0, 0, 0)
                    for _, wd in pairs(wheels.wheels) do 
                        avgWheelPos = avgWheelPos + vec3(v.data.nodes[wd.node1].pos)
                    end
                    avgWheelPos = avgWheelPos / total
                    
                    local frontPropulsed = 0
                    local rearPropulsed = 0
                    
                    for _, wd in pairs(wheels.wheels) do 
                        if wd.isPropulsed then 
                            local wheelNodePos = vec3(v.data.nodes[wd.node1].pos)
                            local wheelVector = wheelNodePos - avgWheelPos
                            local dotForward = vectorForward:dot(wheelVector)
                            
                            if dotForward >= 0 then 
                                frontPropulsed = frontPropulsed + 1
                            else 
                                rearPropulsed = rearPropulsed + 1
                            end 
                        end 
                    end
                    
                    if frontPropulsed > 0 and rearPropulsed > 0 then 
                        drivetrain = "AWD" 
                    elseif frontPropulsed > 0 then 
                        drivetrain = "FWD" 
                    else 
                        drivetrain = "RWD" 
                    end
                else
                    drivetrain = "AWD"
                end
            else
                 drivetrain = "RWD" 
            end
        end

        if wheels and wheels.wheelRotators then
            for _, w in pairs(wheels.wheelRotators) do
                if w.brakeTorque then brakeTorque = brakeTorque + w.brakeTorque end
            end
        end

        if v and v.data and v.data.wheels then
            for i = 0, tableSizeC(v.data.wheels or {}) - 1 do
                local w = v.data.wheels[i]
                if w and (w.hasTire == nil or w.hasTire) then
                    avgFriction = avgFriction + (w.noLoadCoef or 1.0)
                    frictionCount = frictionCount + 1
                end
            end
            if frictionCount > 0 then avgFriction = avgFriction / frictionCount end
        end

        local gearboxes = powertrain.getDevicesByCategory("gearbox")
        if gearboxes and gearboxes[1] then
            local t = gearboxes[1].type
            if t == "automaticGearbox" then gearboxType = "Automatic"
            elseif t == "cvtGearbox" then gearboxType = "CVT"
            elseif t == "dctGearbox" then gearboxType = "DCT"
            elseif t == "manualGearbox" then gearboxType = "Manual"
            elseif t == "sequentialGearbox" then gearboxType = "Sequential"
            else gearboxType = "Other" end
            gearCount = gearboxes[1].gearsForward or (gearboxes[1].config and gearboxes[1].config.gearsForward) or 0
        end

        local combustionEngines = powertrain.getDevicesByType("combustionEngine")
        local hasTurbo, hasSupercharger = false, false
        for _, en in pairs(combustionEngines) do
            if en.turbocharger and en.turbocharger.isExisting then hasTurbo = true end
            if en.supercharger and en.supercharger.isExisting then hasSupercharger = true end
        end
        if hasTurbo and hasSupercharger then inductionType = "Turbo+SC"
        elseif hasTurbo then inductionType = "Turbo"
        elseif hasSupercharger then inductionType = "SC" end

        obj:queueGameEngineLua(string.format(
            "extensions.performanceLimiter.setBulkData(%f,%f,%f,%f,%f,'%s',%d,%d,%f,'%s',%d,'%s')",
            hp, torque, weight, maxRPM, brakeTorque, drivetrain, propulsed, total,
            avgFriction, gearboxType, gearCount, inductionType
        ))
    ]])

    dataCollected = true
end

M.setBulkData = function(hp, torque, weight, maxRPM, brakeTorque, drivetrain, propulsed, total, avgFriction, gearboxType, gearCount, inductionType)
    vdata.hp = math.ceil(hp)
    vdata.perfPower = vdata.hp
    vdata.torqueNm = math.ceil(torque)
    vdata.perfTorque = vdata.torqueNm
    vdata.weight = math.ceil(weight)
    vdata.maxRPM = maxRPM
    vdata.brakeTorque = brakeTorque
    vdata.drivetrain = drivetrain
    vdata.propulsedWheels = propulsed
    vdata.totalWheels = total
    vdata.avgFriction = avgFriction
    vdata.gearboxType = gearboxType
    vdata.gearCount = gearCount
    vdata.inductionType = inductionType
end

M.setHP = function(h) vdata.hp = math.ceil(h) vdata.perfPower = vdata.hp end
M.setTorque = function(t) vdata.torqueNm = math.ceil(t) vdata.perfTorque = vdata.torqueNm end
M.setWeight = function(w) vdata.weight = math.ceil(w) end
M.setDrivetrain = function(d, p, t) vdata.drivetrain = d vdata.propulsedWheels = p vdata.totalWheels = t end
M.setBrakeTorque = function(b) vdata.brakeTorque = b end
M.setAvgFriction = function(f) vdata.avgFriction = f end
M.setMaxRPM = function(r) vdata.maxRPM = r end
M.setGearboxType = function(g) vdata.gearboxType = g end
M.setGearCount = function(c) vdata.gearCount = c end
M.setInductionType = function(i) vdata.inductionType = i end

M.getVehicleData = function()
    return vdata
end

local function onReceiveLimit(limitStr)
    local newLimit = tonumber(limitStr)
    if newLimit then
        serverLimit = newLimit
        vdata.serverMaxRating = serverLimit
        updateUI()
    end
end

local function try_register()
    if M.registered_events then return end
    if type(AddEventHandler) == "function" then
        AddEventHandler("PerfModReceiveLimit", onReceiveLimit)
        AddEventHandler("PerfModFreezeVehicle", freeze)
        AddEventHandler("PerfModUnfreezeVehicle", unfreeze)
        M.registered_events = true
    end
end

local function sendToServer()
    if not (dataCollected and vdata.hp > 0 and vdata.weight > 0) then
        return false
    end

    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent("PerfModCheckVehicle", buildVehicleJSON())
        return true
    end
    return false
end

local function onUpdate(dt)
    if not M.registered_events then
        try_register()
    end

    lastUpdate = lastUpdate + dt
    lastSend = lastSend + dt
    lastFreezeCheck = lastFreezeCheck + dt

    if lastUpdate >= 1.0 then
        lastUpdate = 0
        collect()
    end

    if lastSend >= 0.5 then
        lastSend = 0

        if dataCollected and vdata.hp > 0 and vdata.weight > 0 then
            local ratingData = calculatePI(vdata, serverLimit)

            vdata.rating = ratingData.rating
            vdata.class = ratingData.class
            vdata.ratingRounded = ratingData.ratingRounded
            vdata.serverMaxRating = serverLimit

            updateUI()
            sendToServer()
        end
    end

    if frozen and lastFreezeCheck >= 0.5 then
        lastFreezeCheck = 0
        local v = be:getPlayerVehicle(0)
        if v then
            core_vehicleBridge.executeAction(v, 'setFreeze', true)
        end
    end
end

M.onUpdate = onUpdate
M.requestServerLimit = requestLimit

try_register()

return M
