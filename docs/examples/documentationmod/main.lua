tm.os.Log(tm.GetDocs())

function onPlayerJoined(player)
    tm.playerUI.AddUILabel(player.playerId, "whereToLook", "Documentation has now")
    tm.playerUI.AddUILabel(player.playerId, "whereToLook2", "been generated and can")
    tm.playerUI.AddUILabel(player.playerId, "whereToLook3", "be found (for the host)")
    tm.playerUI.AddUILabel(player.playerId, "whereToLook3", "in this mods logs")
    tm.playerUI.AddUILabel(player.playerId, "spacer", "")
    tm.playerUI.AddUILabel(player.playerId, "whereToLook4", "Steam\\steamapps\\common\\")
    tm.playerUI.AddUILabel(player.playerId, "whereToLook4", "Trailmakers\\mods")
    tm.playerUI.AddUILabel(player.playerId, "whereToLook5", "documentationmod.log")
end
tm.players.OnPlayerJoined.add(onPlayerJoined)