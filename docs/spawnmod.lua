

function update()
    
    playerList = tm.players.CurrentPlayers()
    for key,player in pairs(playerList) do
        pos = tm.players.GetPlayerTransform(player.playerId).GetPosition()
        
        if( pos != nil) then
            tm.playerUI.SetUIValue(player.playerId, "playerPosX", "" .. pos.x)
            tm.playerUI.SetUIValue(player.playerId, "playerPosY", "" .. pos.y)
            tm.playerUI.SetUIValue(player.playerId, "playerPosZ", "" .. pos.z)
        end
    end
end


function addUiForPlayer(playerId)

    ----------------
    tm.playerUI.AddUIButton(playerId, "setGravityBtn", "setGravity", onSetGravity)
    tm.playerUI.AddUIText(playerId, "setGravityTxt", "14", onSetGravityTxt)

    -----------------
    tm.playerUI.AddUIButton(playerId, "spawnBarrel", "PFB_Barrel ", spawnBarrel, nil)
    tm.playerUI.AddUIButton(playerId, "cleanup", "Cleanup spawns ", onCleanupSpawns, nil)

    tm.playerUI.AddUIText(playerId, "playerPosX", "0", onPlayerPosXText)
    tm.playerUI.AddUIText(playerId, "playerPosY", "0", onPlayerPosXText)
    tm.playerUI.AddUIText(playerId, "playerPosZ", "0", onPlayerPosXText)


end
---------------------------------------------------------
lastGravity = 14
function onSetGravity(callbackData)
    tm.physics.SetGravity(lastGravity)
end
function onSetGravityTxt(callbackData)    
    lastGravity = tonumber(callbackData.value)
end

function spawnBarrel(callbackData)
    pos = tm.players.GetPlayerTransform(callbackData.playerId).GetPosition()
    
    for i=1,10 do 
        for j=1,10 do 
            tm.physics.SpawnObject(tm.vector3.Create(pos.x+10+i*2, pos.y, pos.z+10+j*2), "PFB_Barrel")
        end
    end
end
function onCleanupSpawns(callbackData)    
    tm.physics.ClearAllSpawns()
end




function onPlayerJoined(player)
    tm.os.Log("player joined")
    
	addUiForPlayer(player.playerId)

end

tm.players.OnPlayerJoined.add(onPlayerJoined)