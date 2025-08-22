-- Chaos Mod - Ultimate chaos and entertainment!
-- Expanded from MegadrillSeat with tons of fun effects
-- Uses only the public tm.* API

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

-- Cooldowns and limits
local COOLDOWN_SEC = 2.0  -- Universal cooldown for all abilities
local PULSE_RADIUS = 50.0
local PULSE_FORCE = 200000
local MAX_SPAWNS_PER_ABILITY = 50

-- Audio constants  
local AUDIO = {
    MEGADRILL_PULSE = "IGC_PIO_MegaDrill_Death_FinalExplosion",
    MEGADRILL_ALT = "BLCK_WPN_EMPCannon_Fire",
    SHIELD_ACTIVATE = "BLCK_WPN_ShieldBattery_Activate",
    SHIELD_PULSE = "NPC_Enemy_Shields_Activate",
    WAVE_RIPPLE = "Waves_Ocean_Start",
    FIREWORKS = "BLCK_Vanity_Firework_Explode",
    FIREWORKS_SHOOT = "BLCK_Vanity_Firework_Shoot",
    CONFETTI = "LvlObj_ConfettiCelebration",
    WHALE = "NPC_Animal_Whale_Movement",
    WHALE_BIG = "NPC_Animal_Whale_Big_Start",
    EXPLOSION = "Ending_Explosion_Stringer",
    TELEPORT = "LvlObj_TeleportStation_activate",
    WIND = "Amb_Basicwind_start",
    LANDMINE = "LvlObj_LandmineExplosion_explosion"
}

-- Spawnable prefabs
local PREFABS = {
    EXPLOSION_LARGE = "PFB_Explosion_Large",
    EXPLOSION_XL = "PFB_Explosion_XL",
    EXPLOSION_MEDIUM = "PFB_Explosion_Medium",
    WHALE = "PFB_Whale", 
    BARREL = "PFB_Barrel",
    BARREL_EXPLOSIVE = "PFB_ExplosiveBarrel",
    CHASER = "PFB_ChaserAI",
    RUNNER = "PFB_Runner",
    NUGGET_THIEF = "PFB_NuggetThief",
    SHEEP = "PFB_Sheep",
    LANDMINE = "PFB_Mine",
    ENERGY_SHIELD = "PFB_Red_EnergyShield",
    SPACE_RING_1 = "PFB_SpaceRing_01",
    SPACE_RING_2 = "PFB_SpaceRing_02",
    SPACE_RING_3 = "PFB_SpaceRing_03"
}

-- =============================================================================
-- CORE SYSTEMS
-- =============================================================================

local cooldowns = {}  -- [playerId_ability] = timestamp
local pulseShields = {}  -- Track pulse shields for auto-cleanup

local function now()
    return tm.os.GetRealtimeSinceStartup()
end

-- Clean up expired pulse shields
local function cleanupExpiredPulseShields()
    local currentTime = now()
    for i = #pulseShields, 1, -1 do
        local shield = pulseShields[i]
        if currentTime - shield.spawnTime > 1.0 then  -- 1 second cleanup
            if shield.object then
                tm.physics.DespawnObject(shield.object)
            end
            table.remove(pulseShields, i)
        end
    end
end

local function canUse(playerId, ability)
    local key = playerId .. "_" .. ability
    local t = now()
    local last = cooldowns[key] or 0
    return (t - last) >= COOLDOWN_SEC
end

local function useAbility(playerId, ability, func)
    if not canUse(playerId, ability) then
        tm.playerUI.SetUIValue(playerId, "status", "Cooldown! Wait " .. COOLDOWN_SEC .. "s")
        return false
    end
    
    cooldowns[playerId .. "_" .. ability] = now()
    local success, error = pcall(func, playerId)
    
    if not success then
        tm.playerUI.SetUIValue(playerId, "status", "Error: " .. tostring(error))
        tm.os.Log("Soundboard error in " .. ability .. ": " .. tostring(error))
        return false
    end
    
    return true
end

local function setStatus(playerId, text)
    tm.playerUI.SetUIValue(playerId, "status", text)
end

-- Safe object spawning with fallbacks
local function safeSpawn(position, prefab, fallback)
    local spawned = tm.physics.SpawnObject(position, prefab)
    if not spawned and fallback then
        spawned = tm.physics.SpawnObject(position, fallback)
    end
    return spawned
end

-- Safe audio playing with fallbacks
local function safeAudio(position, audioName, fallback, volume)
    volume = volume or 2.0
    tm.audio.PlayAudioAtPosition(audioName, position, volume)
    if fallback then
        tm.audio.PlayAudioAtPosition(fallback, position, volume * 0.5)
    end
end

-- =============================================================================
-- PHASE 1: ENHANCED MEGADRILL PULSE
-- =============================================================================


local function createMegadrillPulse(playerId)
    local playerPos = tm.players.GetPlayerTransform(playerId).GetPosition()
    
    -- Create pulse wave at player's ground level
    local center = tm.vector3.Create(playerPos.x, playerPos.y, playerPos.z)
    
    -- Play energy shield activation audio first
    safeAudio(center, AUDIO.SHIELD_ACTIVATE, AUDIO.SHIELD_PULSE, 2.0)
    safeAudio(center, AUDIO.WAVE_RIPPLE, nil, 1.5)
    
    -- Create single energy shield at player's exact position
    local shield = tm.physics.SpawnObject(center, PREFABS.ENERGY_SHIELD)
    if shield then
        -- Make the shield larger for more dramatic effect
        local transform = shield.GetTransform()
        if transform and transform.SetScale then
            transform.SetScale(3.0, 3.0, 3.0)  -- 3x larger than normal
        end
        
        -- Track shield for auto-cleanup
        table.insert(pulseShields, {
            object = shield,
            spawnTime = now()
        })
    end
    
    -- Apply OUTWARD forces to all players within pulse radius
    local allPlayers = tm.players.CurrentPlayers()
    local affected = 0
    
    for _, targetPlayer in pairs(allPlayers) do
        if targetPlayer.playerId ~= playerId then  -- Don't affect triggering player
            local targetPos = tm.players.GetPlayerTransform(targetPlayer.playerId).GetPosition()
            
            -- Calculate HORIZONTAL distance from pulse center (ignore Y for better radial effect)
            local pushDir = tm.vector3.Create(
                targetPos.x - center.x,
                0,  -- No vertical component in distance calc
                targetPos.z - center.z
            )
            local distance = pushDir.Magnitude()
            
            if distance < PULSE_RADIUS and distance > 0.1 then
                -- Calculate force based on distance (closer = stronger push)
                local forceMult = (PULSE_RADIUS - distance) / PULSE_RADIUS
                local force = forceMult * PULSE_FORCE
                
                -- Normalize HORIZONTAL direction with enhanced upward lift for dramatic shockwave
                if distance > 0 then
                    pushDir = tm.vector3.Create(
                        pushDir.x / distance,    -- Radial X direction
                        0.5,                     -- Enhanced upward component for shockwave effect
                        pushDir.z / distance     -- Radial Z direction
                    )
                end
                
                -- Push their structures OUTWARD from pulse center
                local structures = tm.players.GetPlayerStructures(targetPlayer.playerId)
                if structures then
                    for _, struct in pairs(structures) do
                        struct.AddForce(
                            pushDir.x * force,
                            pushDir.y * force,
                            pushDir.z * force
                        )
                    end
                end
                
                affected = affected + 1
            end
        end
    end
    
    -- Triggering player stays grounded - no upward force applied
    
    setStatus(playerId, "🛡️ ENERGY SHOCKWAVE! Repelled " .. affected .. " players")
end


-- =============================================================================
-- PHASE 3: DESTRUCTION EFFECTS  
-- =============================================================================

local function barrelRain(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local spawned = 0
    
    for i = 1, MAX_SPAWNS_PER_ABILITY do
        local spawnPos = tm.vector3.Create(
            pos.x + math.random(-25, 25),
            pos.y + 30 + math.random(0, 20),
            pos.z + math.random(-25, 25)
        )
        
        -- 30% chance for explosive barrels
        local prefab = (math.random() > 0.7) and PREFABS.BARREL_EXPLOSIVE or PREFABS.BARREL
        if safeSpawn(spawnPos, prefab) then
            spawned = spawned + 1
        end
    end
    
    safeAudio(pos, AUDIO.WIND, nil, 2.0)
    setStatus(playerId, "🛢️ BARREL RAIN! Spawned " .. spawned .. " barrels")
end

local function fireworksShow(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local explosions = 0
    
    for i = 1, 25 do
        local offset = tm.vector3.Create(
            math.random(-40, 40),
            math.random(10, 35),
            math.random(-40, 40)
        )
        local explosionPos = tm.vector3.Create(
            pos.x + offset.x,
            pos.y + offset.y, 
            pos.z + offset.z
        )
        
        -- Mix of different explosion sizes
        local prefab = (math.random() > 0.5) and PREFABS.EXPLOSION_LARGE or PREFABS.EXPLOSION_MEDIUM
        if safeSpawn(explosionPos, prefab) then
            explosions = explosions + 1
        end
    end
    
    safeAudio(pos, AUDIO.FIREWORKS, AUDIO.FIREWORKS_SHOOT, 3.0)
    safeAudio(pos, AUDIO.CONFETTI, nil, 2.0)
    setStatus(playerId, "🎆 FIREWORKS SHOW! " .. explosions .. " explosions")
end

local function mineField(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local mines = 0
    
    for i = 1, 15 do
        local minePos = tm.vector3.Create(
            pos.x + math.random(-12, 12),
            pos.y + 1,
            pos.z + math.random(-12, 12)
        )
        
        -- Use only safe, known prefabs
        if safeSpawn(minePos, "PFB_ExplosiveCrate") then
            mines = mines + 1
        elseif safeSpawn(minePos, "PFB_ExplosiveBarrel") then
            mines = mines + 1
        end
    end
    
    safeAudio(pos, AUDIO.LANDMINE, nil, 1.5)
    setStatus(playerId, "💣 EXPLOSIVE FIELD! Placed " .. mines .. " explosive objects")
end

local function gravityBomb(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    
    -- Extreme gravity for dramatic effect
    tm.physics.SetGravity(50)  -- 3.5x normal gravity
    
    -- Add visual and audio feedback
    safeSpawn(pos, PREFABS.EXPLOSION_MEDIUM)
    safeAudio(pos, AUDIO.EXPLOSION, nil, 2.0)
    
    -- Push all structures down hard to show the effect immediately
    local allPlayers = tm.players.CurrentPlayers()
    local affected = 0
    for _, player in pairs(allPlayers) do
        local structures = tm.players.GetPlayerStructures(player.playerId)
        if structures then
            for _, struct in pairs(structures) do
                struct.AddForce(0, -PULSE_FORCE * 0.5, 0)  -- Strong downward force
                affected = affected + 1
            end
        end
    end
    
    setStatus(playerId, "🌍 GRAVITY BOMB! Heavy gravity + " .. affected .. " vehicles pushed down!")
end

-- =============================================================================
-- PHASE 4: CREATURE SPAWNS
-- =============================================================================

local function whaleRain(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local whales = 0
    
    -- Simple whale spawning without any force manipulation
    for i = 1, 5 do
        local whalePos = tm.vector3.Create(
            pos.x + math.random(-20, 20),
            pos.y + 10,  -- Fixed height, close to ground
            pos.z + math.random(-20, 20)
        )
        
        -- Simple spawn without trying to modify the object
        if tm.physics.SpawnObject(whalePos, "PFB_Whale") then
            whales = whales + 1
        end
    end
    
    safeAudio(pos, AUDIO.WHALE, AUDIO.WHALE_BIG, 3.0)
    
    if whales > 0 then
        setStatus(playerId, "🐋 WHALE PARADE! " .. whales .. " whales summoned nearby")
    else
        setStatus(playerId, "🐋 WHALE PARADE! No whales spawned")
    end
end

local function animalSwarm(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local animals = {PREFABS.CHASER, PREFABS.RUNNER, PREFABS.NUGGET_THIEF}
    local spawned = 0
    
    for i = 1, 20 do
        local animalPos = tm.vector3.Create(
            pos.x + math.random(-15, 15),
            pos.y + math.random(2, 8),
            pos.z + math.random(-15, 15)
        )
        
        local animal = animals[math.random(1, #animals)]
        if safeSpawn(animalPos, animal) then
            spawned = spawned + 1
        end
    end
    
    setStatus(playerId, "🐝 ANIMAL SWARM! " .. spawned .. " creatures spawned")
end

local function sheepInvasion(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local sheep = 0
    
    for i = 1, 15 do
        local sheepPos = tm.vector3.Create(
            pos.x + math.random(-12, 12),
            pos.y + 1,
            pos.z + math.random(-12, 12)
        )
        
        if safeSpawn(sheepPos, PREFABS.SHEEP) then
            sheep = sheep + 1
        end
    end
    
    setStatus(playerId, "🐑 SHEEP INVASION! " .. sheep .. " peaceful sheep")
end

-- =============================================================================
-- PHASE 5: PHYSICS CHAOS
-- =============================================================================

local function slowMotion(playerId)
    tm.physics.SetTimeScale(0.2)
    setStatus(playerId, "⏰ SLOW MOTION activated!")
end

local function speedUp(playerId)
    tm.physics.SetTimeScale(2.0)
    setStatus(playerId, "⚡ SPEED UP activated!")
end

local function lowGravity(playerId)
    tm.physics.SetGravity(3)
    setStatus(playerId, "🚀 LOW GRAVITY enabled!")
end

local function reverseGravity(playerId)
    tm.physics.SetGravity(-8)
    setStatus(playerId, "🙃 REVERSE GRAVITY - everything falls UP!")
end

local function structureLauncher(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local allPlayers = tm.players.CurrentPlayers()
    local launched = 0
    
    -- Visual effect first
    safeSpawn(pos, PREFABS.EXPLOSION_LARGE)
    safeAudio(pos, AUDIO.EXPLOSION, nil, 2.0)
    
    for _, player in pairs(allPlayers) do
        local structures = tm.players.GetPlayerStructures(player.playerId)
        if structures and #structures > 0 then
            for _, struct in pairs(structures) do
                if struct and struct.AddForce then
                    -- Massive upward force with slight random spread
                    struct.AddForce(
                        math.random(-10000, 10000),   -- Small random X
                        PULSE_FORCE * 3,              -- Huge upward force
                        math.random(-10000, 10000)    -- Small random Z
                    )
                    launched = launched + 1
                end
            end
        else
            -- If no structures, try to affect the player's transform area
            local playerTransform = tm.players.GetPlayerTransform(player.playerId)
            if playerTransform then
                -- Create explosion at player position for visual feedback
                safeSpawn(playerTransform.GetPosition(), PREFABS.EXPLOSION_MEDIUM)
            end
        end
    end
    
    if launched == 0 then
        setStatus(playerId, "🚀 STRUCTURE LAUNCHER! No vehicles found to launch (try building something first)")
    else
        setStatus(playerId, "🚀 STRUCTURE LAUNCHER! " .. launched .. " vehicles launched!")
    end
end

-- =============================================================================
-- PHASE 6: ENVIRONMENTAL EFFECTS
-- =============================================================================

local function teleportParty(playerId)
    local playerPos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local allPlayers = tm.players.CurrentPlayers()
    local teleported = 0
    
    -- Create a party spawn point at the triggering player's location
    for _, player in pairs(allPlayers) do
        if player.playerId ~= playerId then
            local partyPos = tm.vector3.Create(
                playerPos.x + math.random(-10, 10),
                playerPos.y + 5,
                playerPos.z + math.random(-10, 10)
            )
            
            tm.players.SetSpawnPoint(
                player.playerId,
                "party_zone",
                partyPos,
                tm.vector3.Create(0, 0, 0)
            )
            
            -- Attempt to teleport (may not work in all game modes)
            tm.players.TeleportPlayerToSpawnPoint(player.playerId, "party_zone", true)
            teleported = teleported + 1
        end
    end
    
    safeAudio(playerPos, AUDIO.TELEPORT, nil, 2.0)
    setStatus(playerId, "🌀 TELEPORT PARTY! Attempted to bring " .. teleported .. " players")
end

local function cleanupAll(playerId)
    tm.physics.ClearAllSpawns()
    -- Also clear our shield tracking
    pulseShields = {}
    setStatus(playerId, "🧹 CLEANUP COMPLETE! All spawned objects removed")
end

local function cleanupShieldsOnly(playerId)
    local cleaned = 0
    for i = #pulseShields, 1, -1 do
        local shield = pulseShields[i]
        if shield.object then
            tm.physics.DespawnObject(shield.object)
            cleaned = cleaned + 1
        end
        table.remove(pulseShields, i)
    end
    setStatus(playerId, "🛡️ SHIELD CLEANUP! Removed " .. cleaned .. " energy shields")
end

local function resetPhysics(playerId)
    tm.physics.SetGravity(14)  -- Normal gravity
    tm.physics.SetTimeScale(1.0)  -- Normal time
    setStatus(playerId, "🔄 PHYSICS RESET - Everything back to normal")
end

-- Safety function to teleport player back to surface if they go underground
local function emergencyTeleport(playerId)
    local playerPos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local safePos = tm.vector3.Create(playerPos.x, 50, playerPos.z)  -- 50 units above ground
    
    tm.players.SetSpawnPoint(
        playerId,
        "emergency_surface",
        safePos,
        tm.vector3.Create(0, 0, 0)
    )
    
    tm.players.TeleportPlayerToSpawnPoint(playerId, "emergency_surface", true)
    setStatus(playerId, "🆘 EMERGENCY TELEPORT! Rescued from underground")
end

-- =============================================================================
-- ENVIRONMENTAL EFFECT – ENERGY-SHIELD BUBBLE
-- =============================================================================
local SHIELD_PREFAB   = "PFB_VikingHarbour_Shield_04" -- Try different shield color
local SHIELD_SCALE    = 12                     -- diameter ≈ 12 m (visible from inside)
local SHIELD_DURATION = 25                     -- seconds before auto-despawn
local SHIELD_KNOCK_CD = 0.25                   -- seconds between pulses
local SHIELD_IMPULSE  = 25000                  -- outward force

-- Generic shield spawning function
local function spawnShieldWithSize(playerId, scale, sizeName)
    local pPos = tm.players.GetPlayerTransform(playerId).GetPosition()
    -- Spawn shield much higher to avoid collision issues with larger shields
    local heightOffset = 30 + (scale * 5)  -- Higher for larger shields
    local center = tm.vector3.Create(pPos.x, math.max(pPos.y + heightOffset, 40), pPos.z)

    local shield = tm.physics.SpawnObject(center, PREFABS.ENERGY_SHIELD)
    if not shield then
        setStatus(playerId, "⚠️ Shield prefab not available - using visual effects instead")
        -- Fallback: create visual shield effect with explosions
        for i = 1, 16 do
            local angle = (i - 1) * (math.pi * 2 / 16)
            local shieldPos = tm.vector3.Create(
                center.x + math.cos(angle) * 15,
                center.y + math.random(-5, 5),
                center.z + math.sin(angle) * 15
            )
            safeSpawn(shieldPos, PREFABS.EXPLOSION_MEDIUM)
        end
        safeAudio(center, AUDIO.SHIELD_ACTIVATE, AUDIO.SHIELD_PULSE, 2.5)
        setStatus(playerId, "🛡️ ENERGY SHIELD visual effect activated!")
        return
    end

    -- Scale shield to specified size
    local transform = shield.GetTransform()
    if transform and transform.SetScale then
        transform.SetScale(scale, scale, scale)
        setStatus(playerId, "🛡️ " .. sizeName .. " SHIELD deployed! " .. math.floor(center.y - pPos.y) .. " units above you")
    else
        setStatus(playerId, "🛡️ " .. sizeName .. " shield spawned at default size")
    end

    -- Light upward force for dramatic effect
    local myStructures = tm.players.GetPlayerStructures(playerId)
    if myStructures then
        for _, struct in pairs(myStructures) do
            if struct and struct.AddForce then
                struct.AddForce(0, PULSE_FORCE * 0.3, 0)  -- Light upward lift
            end
        end
    end

    -- Use energy shield audio for consistency
    safeAudio(center, AUDIO.SHIELD_ACTIVATE, AUDIO.SHIELD_PULSE, 2.5)
end

-- Small shield (2x scale)
local function spawnSmallShield(playerId)
    spawnShieldWithSize(playerId, 2, "SMALL")
end

-- Medium shield (6x scale) 
local function spawnMediumShield(playerId)
    spawnShieldWithSize(playerId, 6, "MEDIUM")
end

-- Large shield (12x scale - the original size, but with better positioning)
local function spawnLargeShield(playerId)
    spawnShieldWithSize(playerId, 12, "LARGE")
end

-- Keep old function name for compatibility
local function spawnShieldBubble(playerId)
    spawnMediumShield(playerId)
end

-- =============================================================================
-- AUTO-CLEANUP SYSTEM FOR PULSE SHIELDS
-- =============================================================================

-- Note: cleanupExpiredPulseShields function is defined earlier in the file
-- and is called on every ability use as a fallback cleanup method

-- =============================================================================
-- UI SETUP
-- =============================================================================

local function onPlayerJoined(p)
    local pid = p.playerId
    
    -- Title and status
    tm.playerUI.AddUILabel(pid, "title", "🎛️ === CHAOS MOD === 🎛️")
    tm.playerUI.AddUIText(pid, "status", "Ready for chaos!", nil)
    
    -- === DESTRUCTION ROW ===
    tm.playerUI.AddUILabel(pid, "destruction_label", "💥 DESTRUCTION:")
    
    tm.playerUI.AddUIButton(pid, "megapulse", "🛡️ Energy Shockwave", function()
        useAbility(pid, "megapulse", createMegadrillPulse)
    end)
    
    tm.playerUI.AddUIButton(pid, "barrels", "🛢️ Barrel Rain", function()
        useAbility(pid, "barrels", barrelRain)
    end)
    
    tm.playerUI.AddUIButton(pid, "fireworks", "🎆 Fireworks Show", function()
        useAbility(pid, "fireworks", fireworksShow)
    end)
    
    tm.playerUI.AddUIButton(pid, "mines", "💣 Mine Field", function()
        useAbility(pid, "mines", mineField)
    end)
    
    tm.playerUI.AddUIButton(pid, "gravbomb", "🌍 Gravity Bomb", function()
        useAbility(pid, "gravbomb", gravityBomb)
    end)
    
    -- === CREATURES ROW ===
    tm.playerUI.AddUILabel(pid, "creatures_label", "🐋 CREATURES:")
    
    tm.playerUI.AddUIButton(pid, "whales", "🐋 Whale Rain", function()
        useAbility(pid, "whales", whaleRain)
    end)
    
    tm.playerUI.AddUIButton(pid, "swarm", "🐝 Animal Swarm", function()
        useAbility(pid, "swarm", animalSwarm)
    end)
    
    tm.playerUI.AddUIButton(pid, "sheep", "🐑 Sheep Invasion", function()
        useAbility(pid, "sheep", sheepInvasion)
    end)
    
    -- === PHYSICS ROW ===
    tm.playerUI.AddUILabel(pid, "physics_label", "⚡ PHYSICS:")
    
    tm.playerUI.AddUIButton(pid, "slowmo", "⏰ Slow Motion", function()
        useAbility(pid, "slowmo", slowMotion)
    end)
    
    tm.playerUI.AddUIButton(pid, "speedup", "⚡ Speed Up", function()
        useAbility(pid, "speedup", speedUp)
    end)
    
    tm.playerUI.AddUIButton(pid, "lowgrav", "🚀 Low Gravity", function()
        useAbility(pid, "lowgrav", lowGravity)
    end)
    
    tm.playerUI.AddUIButton(pid, "flipgrav", "🙃 Reverse Gravity", function()
        useAbility(pid, "flipgrav", reverseGravity)
    end)
    
    tm.playerUI.AddUIButton(pid, "launcher", "🚀 Launch All Vehicles", function()
        useAbility(pid, "launcher", structureLauncher)
    end)
    
    -- === ENVIRONMENTAL ROW ===
    tm.playerUI.AddUILabel(pid, "env_label", "🌀 ENVIRONMENT:")
    
    tm.playerUI.AddUIButton(pid, "teleport", "🌀 Teleport Party", function()
        useAbility(pid, "teleport", teleportParty)
    end)

    tm.playerUI.AddUIButton(pid, "shield_small", "🛡️ Small Shield", function()
        useAbility(pid, "shield_small", spawnSmallShield)
    end)
    
    tm.playerUI.AddUIButton(pid, "shield_medium", "🛡️ Medium Shield", function()
        useAbility(pid, "shield_medium", spawnMediumShield)
    end)
    
    tm.playerUI.AddUIButton(pid, "shield_large", "🛡️ Large Shield", function()
        useAbility(pid, "shield_large", spawnLargeShield)
    end)   
    
    -- === CONTROL ROW ===
    tm.playerUI.AddUILabel(pid, "control_label", "🔧 CONTROLS:")
    
    tm.playerUI.AddUIButton(pid, "cleanup", "🧹 Cleanup All", function()
        useAbility(pid, "cleanup", cleanupAll)
    end)
    
    tm.playerUI.AddUIButton(pid, "cleanup_shields", "🛡️ Cleanup Shields", function()
        useAbility(pid, "cleanup_shields", cleanupShieldsOnly)
    end)
    
    tm.playerUI.AddUIButton(pid, "reset", "🔄 Reset Physics", function()
        useAbility(pid, "reset", resetPhysics)
    end)
    
    tm.playerUI.AddUIButton(pid, "emergency", "🆘 Emergency Teleport", function()
        useAbility(pid, "emergency", emergencyTeleport)
    end)
    
end

-- Hook the join event
tm.players.OnPlayerJoined.add(onPlayerJoined)
