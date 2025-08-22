

function update()

end



function updateKickUIForPlayer0()
    playerList = tm.players.CurrentPlayers()
    
    tm.playerUI.ClearUI(0)
    ---------------------------------------------------------
    for key1,player1 in pairs(playerList) do
        playerName = tm.players.GetPlayerName(player1.playerId)
        tm.playerUI.AddUIButton(0, "kick" .. player1.playerId, "Kick "..playerName, onKickButtonPressed, player1.playerId)
    end

end

---------------------------------------------------------
function onKickButtonPressed(callbackData)
    
    tm.os.Log("callback " .. callbackData.data)
    
    tm.players.Kick(tonumber(callbackData.data))
    
end



function onPlayerJoined(player)
    tm.os.Log("player joined")
    
    updateKickUIForPlayer0()

end

tm.players.OnPlayerJoined.add(onPlayerJoined)

