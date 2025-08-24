

function spawncapsule(callbackData)
    pos = tm.players.GetPlayerTransform(callbackData.playerId).GetPosition()
    for i=1,2 do 
        for j=1,2 do 
            tm.physics.SpawnCustomObject(tm.vector3.Create(pos.x+4+i*3, pos.y+2, pos.z+4+j*3), "teapot", "teapotTex")
        end
    end
    tm.physics.SpawnCustomObjectRigidbody(tm.vector3.Create(pos.x-4, pos.y+2, pos.z+4), "teapot", "teapotTex", false, 1)
end


function onPlayerJoined(player)
    tm.os.Log("player joined")
    
    tm.playerUI.AddUIButton(player.playerId, "spawncapsule", "spawn capsule", spawncapsule, player.playerId)
    
end


tm.players.OnPlayerJoined.add(onPlayerJoined)

tm.physics.AddMesh("OBJ_Mod_Capsule.obj", "teapot")
tm.physics.AddTexture("TEX_Mod_Checker.png", "teapotTex")
