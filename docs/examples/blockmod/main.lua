


function update()
    playerList = tm.players.CurrentPlayers()
    for key,player in pairs(playerList) do
        -- tm.playerUI.ClearUI(player.playerId)
    
        block = tm.players.GetPlayerSelectBlockInBuild(player.playerId)

        if( block != nil) then
            tm.playerUI.AddUIButton(player.playerId, "setColorOnTarget_" .. player.playerId , "Red " .. block.GetName() , onSetColorClicked, player.playerId)
            tm.playerUI.SetUIValue(player.playerId, "setColorOnTarget_" .. player.playerId , "Red " .. block.GetName())
        end
        
    end
    
end


function onSetColorClicked(callbackData)
    
    playerId = tonumber(callbackData.data)

    block = tm.players.GetPlayerSelectBlockInBuild(playerId)
    
    tm.os.Log("callback " .. tostring(block))

    
    block.SetColor(1,0,0,1)
    
    block.SetEnginePower(100000)
    block.SetJetPower(100000)
    
    tm.os.Log(block.GetEnginePower())
    tm.os.Log(block.GetJetPower())

    --block.SetMass(100)

    
    tm.os.Log(block.GetStartHealth())
    tm.os.Log(block.GetMass())

        
end


