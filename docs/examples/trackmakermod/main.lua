local playerDataTable = {}

local gateCount = 0
local recordExists = false
local recordLapTime = 99999999

function onPlayerJoined(player)

    tm.os.Log("player joined. playerId: " .. tostring(player.playerId))

    --Since the mod is running on the server, the data you want to keep track off, for each player, needs to be organized somehow.
    --Here I simply use a table with playerId used as a key.
    playerDataTable[player.playerId] = {
        lastSpawnPosition = tm.vector3.Create(0, 0, 0),
        gateDistance = 2,
        gateWidth = 10,
        isMakingTrack = false,
        trackSaveTable = {},
        inProgressTrackTable = {},
        lapIsInProgress = false,
        lapTimer = 0,
        lapStartTime = 0,
        personalBestTime = 99999999,
        personalBestExists = false
    }
    addUiAndHotkeysForPlayer(player.playerId)
end
tm.players.OnPlayerJoined.add(onPlayerJoined)

--function onPlayerLeft(player)
--end
--tm.players.OnPlayerLeft.add(onPlayerLeft)

function update()

    --Here we loop through the players currently connected to the server (the mod is running serverside) and run the "playerUpdate" function for each one.
    local playerList = tm.players.CurrentPlayers()
    for key, player in pairs(playerList) do
        playerUpdate(player.playerId)
    end
end

function playerUpdate(playerId)

    local playerData = playerDataTable[playerId]

    --update lap timer
    if playerData.lapIsInProgress then
        playerData.lapTimer = tm.os.GetTime() - playerData.lapStartTime
        tm.playerUI.SetUIValue(playerId, "lapTime", "Lap time: " .. string.format("%.3f", playerData.lapTimer))
    end

    --update track building
    if playerData.isMakingTrack then
        local playerPos = tm.players.GetPlayerTransform(playerId).GetPosition()
        local deltaPos = tm.vector3.Create()
        deltaPos = playerPos - playerData.lastSpawnPosition
        local distance = deltaPos.Magnitude()
        tm.playerUI.SetUIValue(playerId, "currentDistancelabel", "Current distance: " .. string.format("%.1f", distance))
        if distance >= playerData.gateDistance then
            playerData.lastSpawnPosition = playerPos
            createGateAndAddToSaveTable(playerId)
        end
    else
        tm.playerUI.SetUIValue(playerId, "currentDistancelabel", "Current distance: N/A")
    end
end

function startTrackMaking(playerId)

    local playerData = playerDataTable[playerId]
    if playerData.isMakingTrack == false then
        playerData.inProgressTrackTable = {}
        playerData.inProgressTrackTable["gates"] = {}
        playerData.isMakingTrack = true
        local playerTransform = tm.players.GetPlayerTransform(playerId)
        local playerPosition = playerTransform.GetPosition()
        local playerRotation = playerTransform.GetRotation()
        local halfWidth = playerData.gateWidth / 2
        spawnStart(playerPosition, playerRotation.y, halfWidth)
        playerDataTable[playerId].lastSpawnPosition = playerPosition
        addStartToSaveTable(playerId, playerPosition, playerRotation.y, halfWidth)
    end
end

function endTrackMaking(playerId)

    local playerData = playerDataTable[playerId]
    if playerData.isMakingTrack == true then
        playerData.isMakingTrack = false
        local playerTransform = tm.players.GetPlayerTransform(playerId)
        local playerPosition = playerTransform.GetPosition()
        local playerRotation = playerTransform.GetRotation()
        local halfWidth = playerData.gateWidth / 2
        spawnFinish(playerPosition, playerRotation.y, halfWidth)
        addFinishToSaveTable(playerId, playerPosition, playerRotation.y, halfWidth)
        playerData.trackSaveTable = playerData.inProgressTrackTable
    end
end

function createGateAndAddToSaveTable(playerId)

    local playerTransform = tm.players.GetPlayerTransform(playerId)
    local playerRotation = playerTransform.GetRotation()
    local halfWidth = playerDataTable[playerId].gateWidth / 2.0

    --Calculate the position of the downward facing ray cast for the left wall
    local leftRayLocalOrigin = tm.vector3.Left() * halfWidth;
    leftRayLocalOrigin.y = halfWidth * 2
    local leftRayWorldOrigin = playerTransform.TransformPoint(leftRayLocalOrigin);
    raycastAndCreateAndSaveWallOnHit(playerId, leftRayWorldOrigin, playerRotation.y)

    --Calculate the position of the downward facing ray cast for the right wall
    local rightRayLocalOrigin = tm.vector3.Right() * halfWidth;
    rightRayLocalOrigin.y = halfWidth * 2
    local rightRayWorldOrigin = playerTransform.TransformPoint(rightRayLocalOrigin);
    raycastAndCreateAndSaveWallOnHit(playerId, rightRayWorldOrigin, playerRotation.y)
end

function raycastAndCreateAndSaveWallOnHit(playerId, rayOrigin, rotationY)

    local direction = tm.vector3.Create(0, -1, 0) --downward facing direction for the ray cast
    local hitPositionOut = tm.vector3.Create(0, 0, 0)
    local hitSomething = tm.physics.Raycast(rayOrigin, direction, hitPositionOut, 100)
    if hitSomething then
        local spawnPosition = hitPositionOut;
        spawnPosition.y = spawnPosition.y + 0.2
        createWall(spawnPosition, rotationY)
        addWallToSaveTable(playerId, spawnPosition, rotationY)
    end
end

function createWall(spawnPos, rotationY)

    local wallObject
    if math.random() > 0.5 then
        wallObject = tm.physics.SpawnObject(spawnPos, "PFB_RacePropTyre-blue")
    else
        wallObject = tm.physics.SpawnObject(spawnPos, "PFB_RacePropTyre-Yellow")
    end
    wallObject.SetIsStatic(true)
    wallObject.GetTransform().SetRotation(0, rotationY, 0)
end

function addWallToSaveTable(playerId, playerPosition, playerY)

    local wallData = {}
    wallData["positionX"] = playerPosition.x
    wallData["positionY"] = playerPosition.y
    wallData["positionZ"] = playerPosition.z

    wallData["rot"] = playerY
    playerDataTable[playerId].inProgressTrackTable["gates"][tostring(gateCount)] = wallData
    gateCount = gateCount + 1
end

function addStartToSaveTable(playerId, playerPosition, playerY, halfWidth)

    local gateData = {}
    gateData["positionX"] = playerPosition.x
    gateData["positionY"] = playerPosition.y
    gateData["positionZ"] = playerPosition.z

    gateData["rot"] = playerY
    gateData["halfWidth"] = halfWidth
    playerDataTable[playerId].inProgressTrackTable["start"] = gateData
end

function addFinishToSaveTable(playerId, playerPosition, playerY, halfWidth)

    local gateData = {}
    gateData["positionX"] = playerPosition.x
    gateData["positionY"] = playerPosition.y
    gateData["positionZ"] = playerPosition.z

    gateData["rot"] = playerY
    gateData["halfWidth"] = halfWidth
    playerDataTable[playerId].inProgressTrackTable["finish"] = gateData
end

--Creates start cosmetics and trigger
function spawnStart(position, rotationY, halfWidth)

    --making the start trigger
    local triggerPosition = tm.vector3.Create(position.x, position.y, position.z)
    local startTrigger = tm.physics.SpawnBoxTrigger(triggerPosition, tm.vector3.Create(halfWidth * 2, 8, 0.5))
    startTrigger.GetTransform().SetRotation(0, rotationY, 0)
    tm.physics.RegisterFunctionToCollisionEnterCallback(startTrigger, "onCollisionStartTrigger")

    --making the start cosmetics
    local rotationYRadians = rotationY / 180 * math.pi
    for widthIndex = -1, 1, 2 do
        local offset = tm.vector3.Create(0, 0, 0);
        offset.x = math.cos(rotationYRadians) * halfWidth * widthIndex
        offset.z = -math.sin(rotationYRadians) * halfWidth * widthIndex

        local spawnPos = position + offset
        local wall = tm.physics.SpawnObject(spawnPos, "PFB_PropWheelStack")
    end
end

--Creates finish cosmetics and trigger
function spawnFinish(position, rotationY, halfWidth)

    --making the finish trigger
    local triggerPosition = tm.vector3.Create(position.x, position.y, position.z)
    local finishTrigger = tm.physics.SpawnBoxTrigger(triggerPosition, tm.vector3.Create(halfWidth * 2, 8, 0.5))
    local wallObjectTransform = finishTrigger.GetTransform()
    wallObjectTransform.SetRotation(tm.vector3.Create(0, rotationY, 0))
    tm.physics.RegisterFunctionToCollisionEnterCallback(finishTrigger, "onCollisionFinishTrigger")

    --making the finish cosmetics
    local rotationYRadians = rotationY / 180 * math.pi
    for widthIndex = -1, 1, 2 do
        local offset = tm.vector3.Create(0, 0, 0);
        offset.x = math.cos(rotationYRadians) * halfWidth * widthIndex
        offset.z = -math.sin(rotationYRadians) * halfWidth * widthIndex
        local spawnPos = position + offset
        tm.physics.SpawnObject(spawnPos, "PFB_PropWheelStack")

        local flagOffset = tm.vector3.Create(0, 0, 0);
        local flagWidth = halfWidth + 1
        flagOffset.x = math.cos(rotationYRadians) * flagWidth * widthIndex
        flagOffset.z = -math.sin(rotationYRadians) * flagWidth * widthIndex
        local flagSpawnPos = position + flagOffset
        tm.physics.SpawnObject(flagSpawnPos, "PFB_KungfuFlaglol")
    end
end

function CreateBuildUI(playerId)

    tm.playerUI.ClearUI(playerId)
    tm.playerUI.AddUIButton(playerId, "switchToRaceMode", "Switch to race mode", onButtonSwitchToRaceMode)
    tm.playerUI.AddUIButton(playerId, "startTrackMaking", "Start track making (J)", onButtonStartTrackMaking)
    tm.playerUI.AddUIButton(playerId, "endTrackMaking", "End track / place finish (K)", onButtonEndTrackMaking)
    tm.playerUI.AddUIButton(playerId, "despawnAll", "Despawn All", onButtonDespawnAll)

    tm.playerUI.AddUILabel(playerId, "spacer", "")

    tm.playerUI.AddUILabel(playerId, "gateWidthlabel", "Gate width")
    tm.playerUI.AddUIText(playerId, "gateWidth", tostring(playerDataTable[playerId].gateWidth), onTextGateWidth)
    tm.playerUI.AddUILabel(playerId, "gateDistancelabel", "Gate distance")
    tm.playerUI.AddUIText(playerId, "gateDistance", tostring(playerDataTable[playerId].gateDistance), onTextGateDinstance)
    tm.playerUI.AddUILabel(playerId, "currentDistancelabel", "Current distance: N/A")
    tm.playerUI.AddUIButton(playerId, "saveTrack", "Save track", onButtonSaveTrack)
    tm.playerUI.AddUIButton(playerId, "loadTrack", "Load track", onButtonLoadTrack)
end


--add UI
function addUiAndHotkeysForPlayer(playerId)

    CreateBuildUI(playerId)
    tm.input.RegisterFunctionToKeyDownCallback(playerId, "startTrackMaking", "j")
    tm.input.RegisterFunctionToKeyDownCallback(playerId, "endTrackMaking", "k")
end

--UI callback functions ========================
--these are registered when creating the UI elements
function onButtonSwitchToRaceMode(callbackData)

    local playerData = playerDataTable[callbackData.playerId]
    tm.playerUI.ClearUI(callbackData.playerId)
    tm.playerUI.AddUIButton(callbackData.playerId, "switchToBuildMode", "Switch to build mode", onSwitchToBuildMode)
    if recordExists then
        tm.playerUI.AddUILabel(callbackData.playerId, "recordLapTime", "Record: " .. string.format("%.3f", recordLapTime))
    else
        tm.playerUI.AddUILabel(callbackData.playerId, "recordLapTime", "Record: N/A")
    end
    if playerData.personalBestExists then
        tm.playerUI.AddUILabel(callbackData.playerId, "personalBestTime", "Personal best: " .. string.format("%.3f", playerData.personalBestTime))
    else
        tm.playerUI.AddUILabel(callbackData.playerId, "personalBestTime", "Personal best: N/A")
    end
    if playerData.lapIsInProgress then
        tm.playerUI.AddUILabel(callbackData.playerId, "lapTime", "Lap time: " .. string.format("%.3f", playerData.lapTimer))
    else
        tm.playerUI.AddUILabel(callbackData.playerId, "lapTime", "Lap time: N/A")
    end
    tm.playerUI.AddUIButton(callbackData.playerId, "clearRecord", "Clear Record", onButtonClearRecord)
    tm.playerUI.AddUIButton(callbackData.playerId, "clearpersonalBest", "Clear Personal Best", onButtonClearPersonalBest)
end

function onButtonClearRecord(callbackData)

    recordLapTime = 99999999
    recordExists = false

    local playerList = tm.players.CurrentPlayers()
    for key, player in pairs(playerList) do
        tm.playerUI.SetUIValue(player.playerId, "recordLapTime", "Record: N/A")
    end
end

function onButtonClearPersonalBest(callbackData)

    local playerData = playerDataTable[callbackData.playerId]
    playerData.personalBestTime = 99999999
    playerData.personalBestExists = false
    tm.playerUI.SetUIValue(callbackData.playerId, "personalBestTime", "Personal best: N/A")
end

function onSwitchToBuildMode(callbackData)

    CreateBuildUI(callbackData.playerId)
end

function onButtonStartTrackMaking(callbackData)

    startTrackMaking(callbackData.playerId)
end

function onButtonEndTrackMaking(callbackData)

    endTrackMaking(callbackData.playerId)
end

function onButtonDespawnAll(callbackData)

    tm.physics.ClearAllSpawns()
    playerDataTable[callbackData.playerId].isMakingTrack = false

    local playerList = tm.players.CurrentPlayers()
    for key, player in pairs(playerList) do
        local playerData = playerDataTable[player.playerId]
        playerData.lapIsInProgress = false
    end
end

function onTextGateDinstance(callbackData)

    playerDataTable[callbackData.playerId].gateDistance = tonumber(callbackData.value)
end

function onTextGateWidth(callbackData)

    playerDataTable[callbackData.playerId].gateWidth = tonumber(callbackData.value)
end

function onButtonSaveTrack(callbackData)

    local jsonString = json.serialize(playerDataTable[callbackData.playerId].trackSaveTable)
    tm.os.WriteAllText_Dynamic("trackData", jsonString)
end

function onButtonLoadTrack(callbackData)

    local file = tm.os.ReadAllText_Dynamic("trackData")
    if file == "" then
        return;
    end
    local trackSaveTable = json.parse(file)
    playerDataTable[callbackData.playerId].trackSaveTable = trackSaveTable

    local jsonString = json.serialize(trackSaveTable)

    for key, value in pairs(trackSaveTable["gates"]) do
        local position = tm.vector3.Create()
        position.x = tonumber(value["positionX"])
        position.y = tonumber(value["positionY"])
        position.z = tonumber(value["positionZ"])
        local rotationY = tonumber(value["rot"])
        createWall(position, rotationY)
    end

    local startData = trackSaveTable["start"]
    if startData then
        local position = tm.vector3.Create()
        position.x = tonumber(startData["positionX"])
        position.y = tonumber(startData["positionY"])
        position.z = tonumber(startData["positionZ"])
        local rotationY = tonumber(startData["rot"])
        local halfWidth = tonumber(startData["halfWidth"])
        spawnStart(position, rotationY, halfWidth)
    end

    local finishData = trackSaveTable["finish"]
    if startData then
        local position = tm.vector3.Create()
        position.x = tonumber(finishData["positionX"])
        position.y = tonumber(finishData["positionY"])
        position.z = tonumber(finishData["positionZ"])
        local rotationY = tonumber(finishData["rot"])
        local halfWidth = tonumber(finishData["halfWidth"])
        spawnFinish(position, rotationY, halfWidth)
    end
end
--UI callback functions end ========================

--collision callback functions ========================
--these are registered with functions: tm.physics.RegisterFunctionToCollisionEnterCallback("nameOfFunction", gameObject)
--or tm.physics.RegisterFunctionToCollisionExitCallback("nameOfFunction", gameObject)
function onCollisionStartTrigger(collidingPlayerId)

    local playerData = playerDataTable[collidingPlayerId]
    if playerData.lapIsInProgress == false then
        playerData.lapIsInProgress = true
        playerData.lapStartTime = tm.os.GetTime()
        playerData.lapTimer = 0
        local playerTransform = tm.players.GetPlayerTransform(collidingPlayerId)
        local playerPos = playerTransform.GetPosition()
        tm.audio.PlayAudioAtPosition("LvlObj_SquareCannon", playerPos)
    end
end

function onCollisionFinishTrigger(collidingPlayerId)

    local playerData = playerDataTable[collidingPlayerId]
    if playerData.lapIsInProgress == true then
        playerData.lapIsInProgress = false
        playerData.lapTimer = tm.os.GetTime() - playerData.lapStartTime
        if recordLapTime > playerData.lapTimer then
            recordLapTime = playerData.lapTimer
            recordExists = true
            
            playerList = tm.players.CurrentPlayers()
            for key, player in pairs(playerList) do
                tm.playerUI.SetUIValue(player.playerId, "recordLapTime", "Record: " .. string.format("%.3f", recordLapTime))
            end
        end
        if playerData.personalBestTime > playerData.lapTimer then
            playerData.personalBestTime = playerData.lapTimer
            playerData.personalBestExists = true
        end
        tm.playerUI.SetUIValue(collidingPlayerId, "personalBestTime", "Personal best: " .. string.format("%.3f", playerData.personalBestTime))
        tm.playerUI.SetUIValue(collidingPlayerId, "lapTime", "Lap time: " .. string.format("%.3f", playerData.lapTimer))
        local playerTransform = tm.players.GetPlayerTransform(collidingPlayerId)
        local playerPos = playerTransform.GetPosition()
        tm.audio.PlayAudioAtPosition("LvlObj_ConfettiCelebration", playerPos)
    end
end
--collision callback functions end ========================