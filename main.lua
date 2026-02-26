-- Chaosboard - Ultimate chaos and entertainment!
-- Uses only the public tm.* API

-- =============================================================================
-- SHOCKWAVE MANAGER (Inlined)
-- =============================================================================

-- Deterministic, frame-rate-independent shockwave spawner
local ShockwaveManager = {}

-- Config  
local SHOCKWAVE_SCALES = {5.0, 4.0, 3.0, 2.0, 1.0, 0.5}  -- Reversed: largest to smallest for outward explosion
local SHOCKWAVE_INTERVAL_SEC = 2.0
local SHOCKWAVE_CLEANUP_DELAY = 4.0  -- Clean up rings 4 seconds after shockwave completes
local SHOCKWAVE_DEBUG = false  -- Disable debug

-- State: Each shockwave: { origin = vec3, t0 = number, nextIndex = 1, rings = { {object=..., born=...}, ... } }
local activeShockwaves = {}

-- Util functions
local function shockwaveTimeNow()
    return tm.os.GetRealtimeSinceStartup()
end

local function shockwaveLog(...)
    if SHOCKWAVE_DEBUG then tm.os.Log("[Shockwave] " .. table.concat({...}, " ")) end
end

local function spawnShockwaveRing(scale, pos, prefab)
    -- Special case: if using seat death explosions, create a ring of explosions
    if prefab == "PFB_Explosion_SeatDeath" then
        local radius = scale  -- Use scale as radius for ring
        local explosionsInRing = math.max(6, math.floor(radius / 2))  -- More explosions for larger rings
        local ringObjects = {}
        
        shockwaveLog("Creating explosion ring: radius =", radius, "explosions =", explosionsInRing)
        
        for i = 0, explosionsInRing - 1 do
            local angle = (i / explosionsInRing) * 2 * math.pi
            local explosionPos = tm.vector3.Create(
                pos.x + math.cos(angle) * radius,
                pos.y,  -- Keep at exact ground level
                pos.z + math.sin(angle) * radius
            )
            
            local obj = tm.physics.SpawnObject(explosionPos, prefab)
            if obj then
                table.insert(ringObjects, obj)
            end
        end
        
        -- Sound will be played by the calling function
        
        -- Return a special structure for multiple objects
        return { objects = ringObjects, born = shockwaveTimeNow(), isRing = true }
    else
        -- Original single object behavior
        local obj = tm.physics.SpawnObject(pos, prefab)
        if not obj then
            shockwaveLog("Spawn failed for scale", scale)
            return nil
        end
        local tf = obj.GetTransform and obj.GetTransform()
        if tf and tf.SetScale then
            tf.SetScale(scale, scale, scale)
        else
            shockwaveLog("Transform/SetScale missing on spawned object")
        end
        return { object = obj, born = shockwaveTimeNow() }
    end
end

-- Public API
function ShockwaveManager.trigger(origin, prefab, opts)
    opts = opts or {}
    local scales = opts.scales or SHOCKWAVE_SCALES
    
    -- Spawn first ring immediately for instant feedback
    local firstRingInfo = spawnShockwaveRing(scales[1], origin, prefab)
    
    local sw = {
        origin    = origin,
        t0        = shockwaveTimeNow(),
        nextIndex = 2,  -- Start from index 2 since we already spawned index 1
        rings     = {},
        scales    = scales,
        interval  = opts.interval or SHOCKWAVE_INTERVAL_SEC,
        prefab    = prefab
    }
    
    if firstRingInfo then table.insert(sw.rings, firstRingInfo) end
    table.insert(activeShockwaves, sw)
    
    shockwaveLog(("Shockwave start @ t=%.2f, origin=(%.2f,%.2f,%.2f), spawned first ring"):format(
        sw.t0, origin.x or 0, origin.y or 0, origin.z or 0))
end

-- Add heartbeat tracking
ShockwaveManager._heartbeat = ShockwaveManager._heartbeat or 0

function ShockwaveManager.update()
    local now = shockwaveTimeNow()
    
    -- Debug heartbeat to verify update timing
    if SHOCKWAVE_DEBUG then
        if now - ShockwaveManager._heartbeat >= 1.0 then
            tm.os.Log(("[Shockwave] heartbeat t=%.2f active=%d"):format(now, #activeShockwaves))
            ShockwaveManager._heartbeat = now
        end
    end
    
    if #activeShockwaves == 0 then return end

    for i = #activeShockwaves, 1, -1 do
        local sw = activeShockwaves[i]
        local scales   = sw.scales
        local interval = sw.interval

        -- Spawn any rings whose scheduled times have passed (catch-up safe)
        while sw.nextIndex <= #scales do
            local dueTime = sw.t0 + (sw.nextIndex - 1) * interval
            if now + 1e-6 < dueTime then break end  -- not yet time
            local scale = scales[sw.nextIndex]
            local ringInfo = spawnShockwaveRing(scale, sw.origin, sw.prefab)
            if ringInfo then table.insert(sw.rings, ringInfo) end
            sw.nextIndex = sw.nextIndex + 1
        end

        -- Check if shockwave is complete (all rings spawned)
        local allSpawned = (sw.nextIndex > #scales)
        if allSpawned and not sw.finished then
            -- Mark as finished and record completion time
            sw.finished = true
            sw.completedAt = now
            shockwaveLog("Shockwave completed, will cleanup in", SHOCKWAVE_CLEANUP_DELAY, "seconds")
        end
    end
end

function ShockwaveManager.clear()
    -- Manually despawn all tracked ring objects
    for _, sw in ipairs(activeShockwaves) do
        for _, ring in ipairs(sw.rings) do
            if ring.isRing and ring.objects then
                -- Handle ring of explosions
                for _, obj in ipairs(ring.objects) do
                    tm.physics.DespawnObject(obj)
                end
            elseif ring.object then
                -- Handle single object
                tm.physics.DespawnObject(ring.object)
            end
        end
    end
    activeShockwaves = {}
    shockwaveLog("Manual clear: despawned all tracked shockwave rings")
end

-- Get count of finished shockwaves (for status messages)
function ShockwaveManager.getFinishedCount()
    local finished = 0
    for _, sw in ipairs(activeShockwaves) do
        if sw.finished then
            finished = finished + 1
        end
    end
    return finished
end

-- Check for and perform automatic cleanup of old completed shockwaves
function ShockwaveManager.autoCleanup()
    local now = shockwaveTimeNow()
    local cleaned = 0
    
    for i = #activeShockwaves, 1, -1 do
        local sw = activeShockwaves[i]
        if sw.finished and sw.completedAt and (now - sw.completedAt >= SHOCKWAVE_CLEANUP_DELAY) then
            -- Clean up this completed shockwave
            for _, ring in ipairs(sw.rings) do
                if ring.object then
                    tm.physics.DespawnObject(ring.object)
                    cleaned = cleaned + 1
                end
            end
            table.remove(activeShockwaves, i)
        end
    end
    
    if cleaned > 0 then
        shockwaveLog("Auto-cleanup: removed", cleaned, "old rings")
    end
    
    return cleaned
end

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

-- Development features
local ENABLE_SPAWNABLE_DUMPER = false  -- Set to false when not needed

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
    LANDMINE = "LvlObj_LandmineExplosion_explosion",
    CHIRPO_TALK = "AVI_NPC_Intercom_Chirpo_Civillian_Default",
    CHIRPO_TYPE = "NPC_Intercom_Typing_AIChirpo",
    CHIRPO_AI = "AVI_NPC_Intercom_Chirpo_AI"
}

-- Spawnable prefabs
local PREFABS = {
    EXPLOSION_LARGE = "PFB_Explosion_Large",
    EXPLOSION_XL = "PFB_Explosion_XL",
    EXPLOSION_MEDIUM = "PFB_Explosion_Medium",
    EXPLOSION_SEAT_DEATH = "PFB_Explosion_SeatDeath",
    EXPLOSION_MICRO = "PFB_Explosion_Micro",
    WHALE = "PFB_Whale", 
    BARREL = "PFB_Barrel",
    BARREL_EXPLOSIVE = "PFB_ExplosiveBarrel",
    CHASER = "PFB_ChaserAI",
    RUNNER = "PFB_Runner",
    NUGGET_THIEF = "PFB_NuggetThief",
    SHEEP = "PFB_Sheep",
    LANDMINE = "PFB_Mine",
    ENERGY_SHIELD = "PFB_Red_EnergyShield",
    -- New cool effects
    POISON_CLOUD = "PFB_PoisonCloud_Explosion",
    FLAMETHROWER = "PFB_FlameThrowerEffect",
    DISPENSABLE_SNOWBALL = "PFB_DispensableSnowball",
    DISPENSABLE_BOULDER = "PFB_DispensableBoulder",
    CRYSTAL_CLUSTER_BLUE = "PFB_CrystalClusterBlue",
    CRYSTAL_CLUSTER_PINK = "PFB_CrystalClusterPink",
    CRYSTAL_SMALL_BLUE = "PFB_CrystalSmall_blue",
    CRYSTAL_SMALL_PINK = "PFB_CrystalSmall_pink",
    RING_OF_FIRE = "PFB_RingofFire",
    BONES_GIANT_RIBCAGE = "PFB_Bones_GiantRibcage",
    BONES_SKELETON = "PFB_Bones_Skeleton_01",
    BONE_RING = "PFB_BoneRing",
    GIANT_BONE_1 = "PFB_GiantBone_1",
    GIANT_BONE_2 = "PFB_GiantBone_2",
    GIANT_BONE_3 = "PFB_GiantBone_3",
    IRON_CRATE = "PFB_IronCrate",
    WOOD_CRATE = "PFB_WoodCrate",
    POWER_CORE_CRATE = "PFB_PowerCoreCrate",
    SPINNER = "PFB_Spinner",
    HAMMER = "PFB_Hammer",
    PUSHER = "PFB_Pusher",
    GIANT_PEARL = "PFB_GiantPearl",
    WINDMILL = "PFB_BigWindMill",
    WINDMILL3 = "PFB_Windmill3",
    RACING_CHECKPOINT = "PFB_RacingCheckPoint",
    BLOCK_HUNT = "PFB_BlockHunt",
    LAVA = "PFB_Lava_Underwater",
    MOVE_PUZZLE_START = "PFB_MovePuzzleStart",
    -- Chirpo variants
    CHIRPO_BLUE = "PFB_Chirpo_Blue",
    CHIRPO_DARK = "PFB_Chirpo_Dark",
    CHIRPO_LIGHTGREEN = "PFB_Chirpo_LightGreen",
    CHIRPO_ORANGE = "PFB_Chirpo_Orange",
    CHIRPO_PURPLE = "PFB_Chirpo_Purple",
    CHIRPO_WHITE = "PFB_Chirpo_White",
    CHIRPO_CAPTAIN = "PFB_Chirpo_CaptainSpeck",
    CHIRPO_STATIONARY = "PFB_Chirpo_Stationary",
    TIMELINE_POD = "PFB_TimelinePodLandingClimbIsland"
}

-- =============================================================================
-- CORE SYSTEMS
-- =============================================================================

local cooldowns = {}  -- [playerId_ability] = timestamp
local pulseShields = {}  -- Track pulse shields for auto-cleanup
local playerPages = {}  -- Track which page each player is on (1 or 2)

local function now()
    return tm.os.GetRealtimeSinceStartup()
end

-- Clean up expired pulse shields
local function cleanupExpiredPulseShields()
    -- Update shockwaves here too for more frequent updates
    ShockwaveManager.update()
    ShockwaveManager.autoCleanup()  -- Check for automatic ring cleanup
    
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
    -- Update shockwave animation system
    ShockwaveManager.update()
    cleanupExpiredPulseShields()
    
    if not canUse(playerId, ability) then
        tm.playerUI.SetUIValue(playerId, "status", "Cooldown! Wait " .. COOLDOWN_SEC .. "s")
        return false
    end
    
    cooldowns[playerId .. "_" .. ability] = now()
    local success, error = pcall(func, playerId)
    
    if not success then
        tm.playerUI.SetUIValue(playerId, "status", "❌ Error in " .. ability)
        tm.os.Log("Chaosboard error in " .. ability .. ": " .. tostring(error))
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
-- DESTRUCTION EFFECTS
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


-- Destruction effects continued

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
    
    -- Play launch sounds from ground level for authenticity
    for i = 1, 8 do
        local launchPos = tm.vector3.Create(
            pos.x + math.random(-15, 15),
            pos.y,
            pos.z + math.random(-15, 15)
        )
        safeAudio(launchPos, AUDIO.FIREWORKS_SHOOT, nil, 2.0)
    end
    
    -- Create firework bursts directly in the sky
    for i = 1, 35 do
        local burstPos = tm.vector3.Create(
            pos.x + math.random(-30, 30),
            pos.y + math.random(20, 40),  -- Medium altitude bursts
            pos.z + math.random(-30, 30)
        )
        
        -- Varied explosion sizes for realistic firework display
        local prefab = PREFABS.EXPLOSION_LARGE
        if math.random() > 0.8 then
            prefab = PREFABS.EXPLOSION_XL  -- 20% chance for big finale bursts
        elseif math.random() > 0.6 then
            prefab = PREFABS.EXPLOSION_MEDIUM  -- 20% chance for smaller bursts
        end
        
        if safeSpawn(burstPos, prefab) then
            explosions = explosions + 1
        end
    end
    
    -- Celebration finale
    safeAudio(pos, AUDIO.FIREWORKS, AUDIO.CONFETTI, 3.0)
    
    setStatus(playerId, "🎆 FIREWORKS SHOW! " .. explosions .. " sky bursts!")
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

local function mineGrid(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local mines = 0
    local GRID_SIZE = 7
    local SPACING = 3.5
    local offset = (GRID_SIZE - 1) * SPACING / 2  -- center grid on player

    for row = 0, GRID_SIZE - 1 do
        for col = 0, GRID_SIZE - 1 do
            local minePos = tm.vector3.Create(
                pos.x + (col * SPACING) - offset,
                pos.y + 0.5,
                pos.z + (row * SPACING) - offset
            )
            if safeSpawn(minePos, PREFABS.LANDMINE, PREFABS.BARREL) then
                mines = mines + 1
            end
        end
    end

    safeAudio(pos, AUDIO.LANDMINE, nil, 1.5)
    setStatus(playerId, "🌸 MINE GRID! " .. mines .. " mines, 7x7!")
end

local function mineSunflower(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local mines = 0
    local GOLDEN_ANGLE = 2.39996  -- 137.508 degrees in radians (phyllotaxis)
    local SCALE = 1.8             -- controls spread of the spiral
    local COUNT = 42

    for i = 1, COUNT do
        local angle = i * GOLDEN_ANGLE
        local radius = SCALE * math.sqrt(i)
        local minePos = tm.vector3.Create(
            pos.x + math.cos(angle) * radius,
            pos.y + 0.5,
            pos.z + math.sin(angle) * radius
        )
        if safeSpawn(minePos, PREFABS.LANDMINE, PREFABS.BARREL) then
            mines = mines + 1
        end
    end

    safeAudio(pos, AUDIO.LANDMINE, nil, 1.5)
    setStatus(playerId, "🌻 SUNFLOWER! " .. mines .. " flower mines!")
end

local function mineChandelier(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local mines = 0

    -- Rings overhead: widens as it descends, like a chandelier
    local rings = {
        { height = 22, count = 6,  radius = 4  },
        { height = 16, count = 10, radius = 9  },
        { height = 10, count = 14, radius = 13 },
        { height = 5,  count = 12, radius = 10 },
    }

    for _, ring in ipairs(rings) do
        for i = 0, ring.count - 1 do
            local angle = (i / ring.count) * 2 * math.pi
            local minePos = tm.vector3.Create(
                pos.x + math.cos(angle) * ring.radius,
                pos.y + ring.height,
                pos.z + math.sin(angle) * ring.radius
            )
            if safeSpawn(minePos, PREFABS.LANDMINE, PREFABS.BARREL) then
                mines = mines + 1
            end
        end
    end

    safeAudio(pos, AUDIO.LANDMINE, nil, 2.0)
    setStatus(playerId, "💎 CHANDELIER! " .. mines .. " mines above!")
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
-- CREATURE SPAWNS
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
            pos.y,  -- At player's ground level  
            pos.z + math.random(-12, 12)
        )
        
        if safeSpawn(sheepPos, PREFABS.SHEEP) then
            sheep = sheep + 1
        end
    end
    
    setStatus(playerId, "🐑 SHEEP INVASION! " .. sheep .. " peaceful sheep")
end

-- =============================================================================
-- PHYSICS CHAOS
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
        setStatus(playerId, "🚀 STRUCTURE LAUNCHER! No vehicles found")
    else
        setStatus(playerId, "🚀 STRUCTURE LAUNCHER! " .. launched .. " vehicles launched!")
    end
end

-- =============================================================================
-- ENVIRONMENTAL EFFECTS
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
    -- Clear our tracking systems first
    pulseShields = {}
    ShockwaveManager.clear()
    
    -- Use safer cleanup approach
    local success, error = pcall(function()
        tm.physics.ClearAllSpawns()
    end)
    
    if success then
        setStatus(playerId, "🧹 CLEANUP COMPLETE! All spawned objects removed")
    else
        setStatus(playerId, "🧹 CLEANUP FAILED! Error: " .. tostring(error))
        tm.os.Log("Cleanup error: " .. tostring(error))
    end
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

local function cleanupShockwaveRings(playerId)
    local cleaned = 0
    -- Manually despawn all tracked shockwave ring objects
    for _, sw in ipairs(activeShockwaves) do
        for _, ring in ipairs(sw.rings) do
            if ring.isRing and ring.objects then
                -- Handle ring of explosions
                for _, obj in ipairs(ring.objects) do
                    tm.physics.DespawnObject(obj)
                    cleaned = cleaned + 1
                end
            elseif ring.object then
                -- Handle single object
                tm.physics.DespawnObject(ring.object)
                cleaned = cleaned + 1
            end
        end
    end
    -- Clear all active shockwaves
    activeShockwaves = {}
    setStatus(playerId, "💫 RING CLEANUP! Removed " .. cleaned .. " objects")
end

local function resetPhysics(playerId)
    tm.physics.SetGravity(14)  -- Normal gravity
    tm.physics.SetTimeScale(1.0)  -- Normal time
    setStatus(playerId, "🔄 PHYSICS RESET - Everything back to normal")
end

-- Safety function to teleport player back to surface if they go underground
local function emergencyTeleport(playerId)
    local playerPos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local safePos = tm.vector3.Create(playerPos.x, playerPos.y + 250, playerPos.z)  -- 250 units above current position

    tm.players.SetSpawnPoint(
        playerId,
        "emergency_surface",
        safePos,
        tm.vector3.Create(0, 0, 0)
    )

    tm.players.TeleportPlayerToSpawnPoint(playerId, "emergency_surface", true)
    setStatus(playerId, "🆘 EMERGENCY TELEPORT! Lifted " .. math.floor(250) .. " units!")
end

local function dumpSpawnables(playerId)
    local names = tm.physics.SpawnableNames()
    table.sort(names)

    local lines = {}
    for _, name in ipairs(names) do
        table.insert(lines, name)
    end

    local output = table.concat(lines, "\n")
    tm.os.WriteAllText_Dynamic("spawnables_current.txt", output)

    setStatus(playerId, "📋 DUMPED! " .. #names .. " spawnables -> spawnables_current.txt")
    tm.os.Log("Spawnable dump complete: " .. #names .. " entries written to spawnables_current.txt")
end


local function barrelFortress(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local barrels = 0
    
    -- Create a square fortress wall pattern around player
    local wallDistance = 6  -- Further from player for stability
    local wallHeight = 3    -- 3 levels high for proper fortress walls
    local barrelSpacing = 3 -- More space between barrels
    
    -- Create 4 walls of a square fortress
    for wall = 1, 4 do
        local wallLength = 5  -- 5 barrels per wall (fewer but more stable)
        for length = 0, wallLength - 1 do
            for height = 0, wallHeight - 1 do
                local barrelPos
                
                if wall == 1 then  -- North wall
                    barrelPos = tm.vector3.Create(pos.x + (length - 2) * barrelSpacing, pos.y + 1 + height * 3, pos.z + wallDistance)
                elseif wall == 2 then  -- East wall
                    barrelPos = tm.vector3.Create(pos.x + wallDistance, pos.y + 1 + height * 3, pos.z + (length - 2) * barrelSpacing)
                elseif wall == 3 then  -- South wall
                    barrelPos = tm.vector3.Create(pos.x + (length - 2) * barrelSpacing, pos.y + 1 + height * 3, pos.z - wallDistance)
                else  -- West wall
                    barrelPos = tm.vector3.Create(pos.x - wallDistance, pos.y + 1 + height * 3, pos.z + (length - 2) * barrelSpacing)
                end
                
                -- Mix of regular and explosive barrels (20% explosive for safety)
                local prefab = (math.random() > 0.8) and PREFABS.BARREL_EXPLOSIVE or PREFABS.BARREL
                if safeSpawn(barrelPos, prefab) then
                    barrels = barrels + 1
                end
            end
        end
    end
    
    safeAudio(pos, AUDIO.SHIELD_ACTIVATE, nil, 2.0)
    setStatus(playerId, "🏰 BARREL FORTRESS! " .. barrels .. " barrels deployed!")
end

local function powerCoreHouse(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local crates = 0
    
    -- Create a house structure with 4 walls, no roof
    local wallDistance = 8  -- Distance from player to walls
    local wallHeight = 4    -- 4 levels high for proper house walls
    local crateSpacing = 3  -- Space between crates
    
    -- Create 4 walls of a square house
    for wall = 1, 4 do
        local wallLength = 6  -- 6 crates per wall for bigger house
        for length = 0, wallLength - 1 do
            for height = 0, wallHeight - 1 do
                local cratePos
                
                if wall == 1 then  -- North wall
                    cratePos = tm.vector3.Create(pos.x + (length - 2.5) * crateSpacing, pos.y + 1 + height * 4, pos.z + wallDistance)
                elseif wall == 2 then  -- East wall  
                    cratePos = tm.vector3.Create(pos.x + wallDistance, pos.y + 1 + height * 4, pos.z + (length - 2.5) * crateSpacing)
                elseif wall == 3 then  -- South wall
                    cratePos = tm.vector3.Create(pos.x + (length - 2.5) * crateSpacing, pos.y + 1 + height * 4, pos.z - wallDistance)
                else  -- West wall
                    cratePos = tm.vector3.Create(pos.x - wallDistance, pos.y + 1 + height * 4, pos.z + (length - 2.5) * crateSpacing)
                end
                
                if safeSpawn(cratePos, PREFABS.POWER_CORE_CRATE) then
                    crates = crates + 1
                end
            end
        end
    end
    
    safeAudio(pos, AUDIO.SHIELD_ACTIVATE, AUDIO.TELEPORT, 2.0)
    setStatus(playerId, "🏠 POWERCORE HOUSE! " .. crates .. " power crates form walls!")
end

local function ringLightShow(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local lights = 0
    
    -- Create energy shield patterns for light show effect
    for pattern = 1, 3 do
        local height = pattern * 8
        local radius = pattern * 6
        
        -- Create circular patterns with energy shields
        for i = 0, 5 do
            local angle = (i / 6) * 2 * math.pi
            local lightPos = tm.vector3.Create(
                pos.x + math.cos(angle) * radius,
                pos.y + height,
                pos.z + math.sin(angle) * radius
            )
            
            -- Use energy shields for light effects
            if safeSpawn(lightPos, PREFABS.ENERGY_SHIELD) then
                lights = lights + 1
            end
        end
    end
    
    -- Add central pillar of light
    for i = 1, 6 do
        local pillarPos = tm.vector3.Create(
            pos.x,
            pos.y + i * 4,
            pos.z
        )
        if safeSpawn(pillarPos, PREFABS.ENERGY_SHIELD) then
            lights = lights + 1
        end
    end
    
    safeAudio(pos, AUDIO.CONFETTI, AUDIO.SHIELD_ACTIVATE, 3.0)
    setStatus(playerId, "💫 RING LIGHT SHOW! " .. lights .. " energy rings!")
end

local function rainbowTrail(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local trails = 0
    local allPlayers = tm.players.CurrentPlayers()
    
    -- Create rainbow trails from triggerer to each other player
    for _, targetPlayer in pairs(allPlayers) do
        if targetPlayer.playerId ~= playerId then
            local targetPos = tm.players.GetPlayerTransform(targetPlayer.playerId).GetPosition()
            
            -- Calculate direction and distance
            local dx = targetPos.x - pos.x
            local dy = targetPos.y - pos.y
            local dz = targetPos.z - pos.z
            local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
            
            -- Create trail of shields with different types for "rainbow" effect
            local steps = math.min(math.floor(distance / 4), 15)  -- Max 15 shields per trail
            for step = 1, steps do
                local progress = step / steps
                local trailPos = tm.vector3.Create(
                    pos.x + dx * progress,
                    pos.y + dy * progress + math.sin(progress * math.pi) * 3,  -- Arc effect
                    pos.z + dz * progress
                )
                
                -- Create trail effect with energy shields
                if safeSpawn(trailPos, PREFABS.ENERGY_SHIELD) then
                    trails = trails + 1
                end
            end
        end
    end
    
    -- If no other players, create a decorative trail pattern
    if trails == 0 then
        for i = 1, 20 do
            local trailPos = tm.vector3.Create(
                pos.x + math.cos(i * 0.3) * i * 2,
                pos.y + math.sin(i * 0.5) * 4,
                pos.z + math.sin(i * 0.3) * i * 2
            )
            if safeSpawn(trailPos, PREFABS.ENERGY_SHIELD) then
                trails = trails + 1
            end
        end
    end
    
    safeAudio(pos, AUDIO.SHIELD_ACTIVATE, AUDIO.SHIELD_PULSE, 2.5)
    setStatus(playerId, "⚡ ENERGY TRAIL! " .. trails .. " energy shields!")
end

local function crystalGarden(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local crystals = 0
    
    -- Create geometric crystal formations
    -- Formation 1: Central spire
    for height = 1, 8 do
        local spirePos = tm.vector3.Create(
            pos.x,
            pos.y + height * 3,
            pos.z
        )
        if safeSpawn(spirePos, PREFABS.ENERGY_SHIELD) then
            crystals = crystals + 1
        end
    end
    
    -- Formation 2: Hexagonal crystal clusters at different heights
    for cluster = 1, 3 do
        local clusterHeight = cluster * 6
        local clusterRadius = cluster * 8
        
        for i = 0, 5 do  -- 6 points of hexagon
            local angle = i * math.pi / 3
            
            -- Main crystal points
            local crystalPos = tm.vector3.Create(
                pos.x + math.cos(angle) * clusterRadius,
                pos.y + clusterHeight,
                pos.z + math.sin(angle) * clusterRadius
            )
            if safeSpawn(crystalPos, PREFABS.ENERGY_SHIELD) then
                crystals = crystals + 1
            end
            
            -- Smaller crystals between main points
            local betweenAngle = angle + math.pi / 6
            local betweenPos = tm.vector3.Create(
                pos.x + math.cos(betweenAngle) * clusterRadius * 0.7,
                pos.y + clusterHeight - 2,
                pos.z + math.sin(betweenAngle) * clusterRadius * 0.7
            )
            if safeSpawn(betweenPos, PREFABS.ENERGY_SHIELD) then
                crystals = crystals + 1
            end
        end
    end
    
    -- Formation 3: Ground-level crystal scattered around base
    for i = 1, 12 do
        local scatterPos = tm.vector3.Create(
            pos.x + math.random(-15, 15),
            pos.y + math.random(1, 4),
            pos.z + math.random(-15, 15)
        )
        if safeSpawn(scatterPos, PREFABS.ENERGY_SHIELD) then
            crystals = crystals + 1
        end
    end
    
    safeAudio(pos, AUDIO.SHIELD_ACTIVATE, AUDIO.SHIELD_PULSE, 2.5)
    setStatus(playerId, "💎 CRYSTAL GARDEN! " .. crystals .. " crystals!")
end

local function halfSphereTop(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local spheres = 0
    
    -- Create a perfect sphere using spherical coordinates
    local centerX = pos.x
    local centerY = pos.y + 15  -- 15 blocks up
    local centerZ = pos.z
    local radius = 8
    
    -- Generate sphere using spherical coordinates for perfect shape
    -- Phi (vertical angle): 0 to pi (top to bottom)
    -- Theta (horizontal angle): 0 to 2*pi (around)
    local phiSteps = 12  -- Number of vertical divisions
    local thetaSteps = 16  -- Number of horizontal divisions
    
    for phiIndex = 0, phiSteps do
        local phi = (phiIndex / phiSteps) * math.pi  -- 0 to pi
        
        -- Skip poles to avoid clustering
        if phiIndex > 0 and phiIndex < phiSteps then
            for thetaIndex = 0, thetaSteps - 1 do
                local theta = (thetaIndex / thetaSteps) * 2 * math.pi  -- 0 to 2*pi
                
                -- Convert spherical to cartesian coordinates
                local x = radius * math.sin(phi) * math.cos(theta)
                local y = radius * math.cos(phi)
                local z = radius * math.sin(phi) * math.sin(theta)
                
                local spherePos = tm.vector3.Create(
                    centerX + x,
                    centerY + y,
                    centerZ + z
                )
                
                if safeSpawn(spherePos, PREFABS.ENERGY_SHIELD) then
                    spheres = spheres + 1
                end
                
                -- Safety limit
                if spheres >= 80 then
                    break
                end
            end
        end
        
        if spheres >= 80 then
            break
        end
    end
    
    -- Add poles manually for perfect sphere completion
    if spheres < 80 then
        -- Top pole
        local topPole = tm.vector3.Create(centerX, centerY + radius, centerZ)
        if safeSpawn(topPole, PREFABS.ENERGY_SHIELD) then
            spheres = spheres + 1
        end
        
        -- Bottom pole
        local bottomPole = tm.vector3.Create(centerX, centerY - radius, centerZ)
        if safeSpawn(bottomPole, PREFABS.ENERGY_SHIELD) then
            spheres = spheres + 1
        end
    end
    
    safeAudio(pos, AUDIO.SHIELD_ACTIVATE, AUDIO.SHIELD_PULSE, 2.5)
    setStatus(playerId, "🌙 TOP HALF-SPHERE! " .. spheres .. " shields form a dome above!")
end

local function shieldTrap(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local spheres = 0
    
    -- Create a perfect shield trap using spherical coordinates
    local centerX = pos.x
    local centerY = pos.y  -- Ground level
    local centerZ = pos.z
    local radius = 12  -- Larger radius to account for shield size
    
    -- Generate complete sphere using spherical coordinates
    -- Accounting for shield object size - fewer, more spaced points
    -- Phi (vertical angle): 0 to pi (top to bottom)
    -- Theta (horizontal angle): 0 to 2*pi (around)
    local phiSteps = 8   -- Fewer divisions to prevent overlap
    local thetaSteps = 10 -- Fewer divisions to prevent overlap
    
    for phiIndex = 0, phiSteps do
        local phi = (phiIndex / phiSteps) * math.pi  -- 0 to pi
        
        -- Skip poles to avoid clustering - handle them separately
        if phiIndex > 0 and phiIndex < phiSteps then
            for thetaIndex = 0, thetaSteps - 1 do
                local theta = (thetaIndex / thetaSteps) * 2 * math.pi  -- 0 to 2*pi
                
                -- Convert spherical to cartesian coordinates
                local x = radius * math.sin(phi) * math.cos(theta)
                local y = radius * math.cos(phi)
                local z = radius * math.sin(phi) * math.sin(theta)
                
                local spherePos = tm.vector3.Create(
                    centerX + x,
                    centerY + y,
                    centerZ + z
                )
                
                if safeSpawn(spherePos, PREFABS.ENERGY_SHIELD) then
                    spheres = spheres + 1
                end
                
                -- Safety limit
                if spheres >= 50 then
                    break
                end
            end
        end
        
        if spheres >= 50 then
            break
        end
    end
    
    -- Add both poles manually for perfect sphere completion
    if spheres < 50 then
        -- Top pole
        local topPole = tm.vector3.Create(centerX, centerY + radius, centerZ)
        if safeSpawn(topPole, PREFABS.ENERGY_SHIELD) then
            spheres = spheres + 1
        end
        
        -- Bottom pole
        local bottomPole = tm.vector3.Create(centerX, centerY - radius, centerZ)
        if safeSpawn(bottomPole, PREFABS.ENERGY_SHIELD) then
            spheres = spheres + 1
        end
    end
    
    safeAudio(pos, AUDIO.SHIELD_ACTIVATE, AUDIO.SHIELD_PULSE, 2.5)
    setStatus(playerId, "🕳️ SHIELD TRAP! " .. spheres .. " shields deployed!")
end

-- =============================================================================
-- NEW CHAOS EFFECTS
-- =============================================================================

local function poisonRain(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local clouds = 0
    
    for i = 1, 15 do
        local cloudPos = tm.vector3.Create(
            pos.x + math.random(-20, 20),
            pos.y + math.random(15, 25),
            pos.z + math.random(-20, 20)
        )
        
        if safeSpawn(cloudPos, PREFABS.POISON_CLOUD) then
            clouds = clouds + 1
        end
    end
    
    safeAudio(pos, AUDIO.EXPLOSION, nil, 2.0)
    setStatus(playerId, "☠️ POISON RAIN! " .. clouds .. " toxic clouds descend from above!")
end

local function snowballFight(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local snowballs = 0
    
    for i = 1, 20 do  -- Reduced from 30 to 20
        local snowPos = tm.vector3.Create(
            pos.x + math.random(-25, 25),
            pos.y + math.random(20, 35),
            pos.z + math.random(-25, 25)
        )
        
        if safeSpawn(snowPos, PREFABS.DISPENSABLE_SNOWBALL) then
            snowballs = snowballs + 1
        end
        
        -- Safety limit
        if snowballs >= 20 then
            break
        end
    end
    
    safeAudio(pos, AUDIO.WIND, nil, 2.0)
    setStatus(playerId, "❄️ SNOWBALL FIGHT! " .. snowballs .. " snowballs ready for battle!")
end

local function crystalCavern(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local crystals = 0
    
    -- Large crystal clusters
    for i = 1, 8 do
        local clusterPos = tm.vector3.Create(
            pos.x + math.random(-15, 15),
            pos.y + math.random(2, 12),
            pos.z + math.random(-15, 15)
        )
        
        local clusterType = (math.random() > 0.5) and PREFABS.CRYSTAL_CLUSTER_BLUE or PREFABS.CRYSTAL_CLUSTER_PINK
        if safeSpawn(clusterPos, clusterType) then
            crystals = crystals + 1
        end
    end
    
    -- Small crystals scattered around
    for i = 1, 20 do
        local smallPos = tm.vector3.Create(
            pos.x + math.random(-20, 20),
            pos.y + math.random(1, 8),
            pos.z + math.random(-20, 20)
        )
        
        local smallType = (math.random() > 0.5) and PREFABS.CRYSTAL_SMALL_BLUE or PREFABS.CRYSTAL_SMALL_PINK
        if safeSpawn(smallPos, smallType) then
            crystals = crystals + 1
        end
    end
    
    safeAudio(pos, AUDIO.SHIELD_ACTIVATE, AUDIO.CONFETTI, 2.5)
    setStatus(playerId, "💎 CRYSTAL CAVERN! " .. crystals .. " crystals!")
end

local function ringOfFire(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local rings = 0
    
    -- Create multiple rings at different heights and distances
    for ring = 1, 5 do
        local ringRadius = ring * 8
        local ringHeight = ring * 3
        
        local ringPos = tm.vector3.Create(
            pos.x,
            pos.y + ringHeight,
            pos.z
        )
        
        if safeSpawn(ringPos, PREFABS.RING_OF_FIRE) then
            rings = rings + 1
        end
    end
    
    safeAudio(pos, AUDIO.EXPLOSION, AUDIO.FIREWORKS, 3.0)
    setStatus(playerId, "🔥 RING OF FIRE! " .. rings .. " blazing rings surround the area!")
end

local function boneGraveyard(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local bones = 0
    
    -- Giant ribcages
    for i = 1, 3 do
        local ribPos = tm.vector3.Create(
            pos.x + math.random(-20, 20),
            pos.y + 2,
            pos.z + math.random(-20, 20)
        )
        
        if safeSpawn(ribPos, PREFABS.BONES_GIANT_RIBCAGE) then
            bones = bones + 1
        end
    end
    
    -- Skeletons
    for i = 1, 5 do
        local skelPos = tm.vector3.Create(
            pos.x + math.random(-15, 15),
            pos.y + 1,
            pos.z + math.random(-15, 15)
        )
        
        if safeSpawn(skelPos, PREFABS.BONES_SKELETON) then
            bones = bones + 1
        end
    end
    
    -- Giant bones scattered around
    local boneTypes = {PREFABS.GIANT_BONE_1, PREFABS.GIANT_BONE_2, PREFABS.GIANT_BONE_3}
    for i = 1, 10 do
        local bonePos = tm.vector3.Create(
            pos.x + math.random(-25, 25),
            pos.y + math.random(1, 5),
            pos.z + math.random(-25, 25)
        )
        
        local boneType = boneTypes[math.random(1, #boneTypes)]
        if safeSpawn(bonePos, boneType) then
            bones = bones + 1
        end
    end
    
    -- Bone rings for spooky effect
    for i = 1, 3 do
        local ringPos = tm.vector3.Create(
            pos.x + math.random(-12, 12),
            pos.y + math.random(5, 10),
            pos.z + math.random(-12, 12)
        )
        
        if safeSpawn(ringPos, PREFABS.BONE_RING) then
            bones = bones + 1
        end
    end
    
    safeAudio(pos, AUDIO.LANDMINE, nil, 2.0)
    setStatus(playerId, "💀 BONE GRAVEYARD! " .. bones .. " bones spawned!")
end

local function boulderAvalanche(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local boulders = 0
    
    for i = 1, 20 do
        local boulderPos = tm.vector3.Create(
            pos.x + math.random(-30, 30),
            pos.y + math.random(25, 40),
            pos.z + math.random(-30, 30)
        )
        
        if safeSpawn(boulderPos, PREFABS.DISPENSABLE_BOULDER) then
            boulders = boulders + 1
        end
    end
    
    safeAudio(pos, AUDIO.EXPLOSION, AUDIO.WIND, 3.0)
    setStatus(playerId, "🪨 BOULDER AVALANCHE! " .. boulders .. " massive boulders tumble down!")
end

local function magneticChaos(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local objects = 0
    
    -- All the chaos objects to spawn
    local chaosObjects = {
        PREFABS.IRON_CRATE,
        PREFABS.WOOD_CRATE,
        PREFABS.POWER_CORE_CRATE,
        PREFABS.WINDMILL,
        PREFABS.WINDMILL3,
        PREFABS.RACING_CHECKPOINT,
        PREFABS.BLOCK_HUNT,
        PREFABS.LAVA
    }
    
    -- Spawn various chaos objects
    for i = 1, 20 do
        local objectPos = tm.vector3.Create(
            pos.x + math.random(-20, 20),
            pos.y + math.random(2, 10),
            pos.z + math.random(-20, 20)
        )
        
        -- Pick random chaos object
        local objectType = chaosObjects[math.random(1, #chaosObjects)]
        if safeSpawn(objectPos, objectType) then
            objects = objects + 1
        end
        
        -- Safety limit
        if objects >= 20 then
            break
        end
    end
    
    safeAudio(pos, AUDIO.SHIELD_PULSE, AUDIO.EXPLOSION, 2.5)
    setStatus(playerId, "🌪️ TOTAL CHAOS! " .. objects .. " objects spawned!")
end

local function chaosTrap(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local traps = 0
    
    -- Spinners
    for i = 1, 8 do
        local spinPos = tm.vector3.Create(
            pos.x + math.random(-15, 15),
            pos.y + 2,
            pos.z + math.random(-15, 15)
        )
        
        if safeSpawn(spinPos, PREFABS.SPINNER) then
            traps = traps + 1
        end
    end
    
    -- Hammers
    for i = 1, 5 do
        local hammerPos = tm.vector3.Create(
            pos.x + math.random(-12, 12),
            pos.y + 3,
            pos.z + math.random(-12, 12)
        )
        
        if safeSpawn(hammerPos, PREFABS.HAMMER) then
            traps = traps + 1
        end
    end
    
    -- Pushers
    for i = 1, 6 do
        local pushPos = tm.vector3.Create(
            pos.x + math.random(-18, 18),
            pos.y + 1,
            pos.z + math.random(-18, 18)
        )
        
        if safeSpawn(pushPos, PREFABS.PUSHER) then
            traps = traps + 1
        end
    end
    
    safeAudio(pos, AUDIO.MEGADRILL_ALT, nil, 2.5)
    setStatus(playerId, "🎪 CHAOS TRAP! " .. traps .. " traps activated!")
end

local function ringShockwave(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local rings = 0
    
    -- Create expanding ring shockwave effect
    for radius = 5, 25, 5 do  -- Rings at radius 5, 10, 15, 20, 25
        local ringPoints = radius * 2  -- More points for larger rings
        
        for i = 0, ringPoints - 1 do
            local angle = (i / ringPoints) * 2 * math.pi
            local ringPos = tm.vector3.Create(
                pos.x + math.cos(angle) * radius,
                pos.y + 2,  -- Ground level
                pos.z + math.sin(angle) * radius
            )
            
            if safeSpawn(ringPos, PREFABS.MOVE_PUZZLE_START) then
                rings = rings + 1
            end
            
            -- Safety limit
            if rings >= 50 then
                break
            end
        end
        
        if rings >= 50 then
            break
        end
    end
    
    safeAudio(pos, AUDIO.MEGADRILL_PULSE, AUDIO.WAVE_RIPPLE, 3.0)
    setStatus(playerId, "💥 RING SHOCKWAVE! " .. rings .. " rings spawned!")
end

local function trueShockwave(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local centerPos = tm.vector3.Create(pos.x, pos.y + 2, pos.z)
    
    -- Trigger new deterministic shockwave system
    ShockwaveManager.trigger(centerPos, PREFABS.MOVE_PUZZLE_START)
    
    -- Play audio effects
    safeAudio(centerPos, AUDIO.MEGADRILL_PULSE, AUDIO.WAVE_RIPPLE, 3.0)
    
    setStatus(playerId, "⚡ TRUE SHOCKWAVE! Outward explosion!")
    
    -- Rings will auto-cleanup 4 seconds after the shockwave completes
end


-- =============================================================================
-- FROZEN TRACKS DLC EFFECTS
-- =============================================================================

local function spawnBuildings(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local spawned = 0

    local buildings = {
        "CliffColoniesHouse_Large_01",
        "CliffColoniesHouse_Large_02",
        "CliffColoniesHouse_MayorHouse",
        "CliffColoniesHouse_Small_01",
        "CliffColoniesHouse_Small_02",
        "CliffColoniesHouse_Small_03",
        "DesertHouse_Antenna_02",
        "DesertHouse_PipeSquare",
        "DesertHouse_SolarPanel_02",
        "DesertHouse_WallAsset_01"
    }

    for i, building in ipairs(buildings) do
        local buildPos = tm.vector3.Create(
            pos.x + math.random(-30, 30),
            pos.y,
            pos.z + math.random(-30, 30)
        )

        if safeSpawn(buildPos, building) then
            spawned = spawned + 1
        end
    end

    safeAudio(pos, AUDIO.TELEPORT, nil, 2.0)
    setStatus(playerId, "🏘️ BUILDINGS! " .. spawned .. " structures spawned!")
end

local function spawnLEDSigns(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local spawned = 0

    local signs = {
        "LED_Sign_Bulldawg", "LED_Sign_Butterfly", "LED_Sign_DitchVibe",
        "LED_Sign_Doge", "LED_Sign_Dragon", "LED_Sign_Hygge",
        "LED_Sign_KeepGoingAB", "LED_Sign_LiveYoung", "LED_Sign_LookStupid",
        "LED_Sign_MyDust", "LED_Sign_NoPeril", "LED_Sign_Rolling_Motar",
        "LED_Sign_TheresAWay", "LED_Sign_Towel", "LED_Sign_Unicorn",
        "LED_Sign_WatchForSigns", "PFB_LED_Sign_3Bridges", "PFB_LED_Sign_Air",
        "PFB_LED_Sign_Beach", "PFB_LED_Sign_Boat", "PFB_LED_Sign_Canal",
        "PFB_LED_Sign_Drag", "PFB_LED_Sign_Track", "PFB_LED_Sign_Valley"
    }

    -- Spawn in a grid pattern for better visibility
    for i = 1, math.min(#signs, 24) do
        local angle = (i / 24) * 2 * math.pi
        local radius = 15 + (i % 3) * 5
        local signPos = tm.vector3.Create(
            pos.x + math.cos(angle) * radius,
            pos.y + 2,
            pos.z + math.sin(angle) * radius
        )

        if safeSpawn(signPos, signs[i]) then
            spawned = spawned + 1
        end
    end

    safeAudio(pos, AUDIO.CONFETTI, nil, 2.0)
    setStatus(playerId, "💡 LED SIGNS! " .. spawned .. " signs spawned!")
end

local function spawnRaceTrack(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local spawned = 0

    local raceItems = {
        "PFB_Race_TurnSign", "PFB_RaceTrack-Speaker", "PFB_RaceTrackStartline",
        "PFB_Rallyramp", "PFB_Race_TurnSign", "PFB_RaceTrack-Speaker"
    }

    -- Create a race track layout
    for i = 1, 12 do
        local trackPos = tm.vector3.Create(
            pos.x + (i - 6) * 8,
            pos.y,
            pos.z + math.sin(i * 0.5) * 10
        )

        local item = raceItems[(i % #raceItems) + 1]
        if safeSpawn(trackPos, item) then
            spawned = spawned + 1
        end
    end

    safeAudio(pos, AUDIO.CONFETTI, AUDIO.FIREWORKS, 2.5)
    setStatus(playerId, "🏁 RACE TRACK! " .. spawned .. " track elements!")
end

local function spawnEnvironment(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local spawned = 0

    local envObjects = {
        "PFB_Trees_HeroOak_01", "PFB_Trees_Oak_01", "PFB_Trees_Oak_02",
        "PFB_Trees_Pine_01", "PFB_Tall__Pruny_SlenderPine_Snow",
        "PFB_Short_Slender_Pine_1", "PFB_Vegetation_Bush_01",
        "PFB_Vegetation_Bush_02", "PFB_INS_Savannah_Fern",
        "PFB_Roots", "Waterfall_Ruins", "PFB_HangingGreenery"
    }

    for i = 1, 25 do
        local envPos = tm.vector3.Create(
            pos.x + math.random(-25, 25),
            pos.y,
            pos.z + math.random(-25, 25)
        )

        local obj = envObjects[math.random(1, #envObjects)]
        if safeSpawn(envPos, obj) then
            spawned = spawned + 1
        end
    end

    safeAudio(pos, AUDIO.WIND, nil, 2.0)
    setStatus(playerId, "🌲 ENVIRONMENT! " .. spawned .. " natural objects!")
end

local function spawnInfrastructure(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local spawned = 0

    local infraItems = {
        "PFB_CurvedBridge", "WoodenBridge_Large", "WoodenBridge_Pole",
        "PFB_BridgePillar", "PFB_ModularSlopeUp_Highseas",
        "PFB_ModularSmallSlope_Highseas", "PFB_PipeHollowBended",
        "PFB_DeliveryStationBLUE", "PFB_DeliveryStationGREEN",
        "PFB_DeliveryStationRED", "PFB_DeliveryStationYELLOW",
        "PFB_Fence_Part_Meadowse_01", "PFB_WoodenFence"
    }

    for i = 1, 15 do
        local infraPos = tm.vector3.Create(
            pos.x + math.random(-20, 20),
            pos.y,
            pos.z + math.random(-20, 20)
        )

        local item = infraItems[math.random(1, #infraItems)]
        if safeSpawn(infraPos, item) then
            spawned = spawned + 1
        end
    end

    safeAudio(pos, AUDIO.TELEPORT, AUDIO.SHIELD_ACTIVATE, 2.0)
    setStatus(playerId, "🌉 INFRASTRUCTURE! " .. spawned .. " structures!")
end

local function spawnSpecialObjects(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local spawned = 0

    local specialItems = {
        "PFB_Blimp", "PFB_Spherecraft", "PFB_SatelliteDish",
        "PFB_LightHouse", "HeroTower_Skyland", "PFB_ExplorationBase",
        "GFX_Dynamic_Water_Buoy", "PFB_Round2Tower", "PFB_Helipad",
        "PFB_Rubble"
    }

    for i, item in ipairs(specialItems) do
        local specialPos = tm.vector3.Create(
            pos.x + math.random(-30, 30),
            pos.y + math.random(5, 15),
            pos.z + math.random(-30, 30)
        )

        if safeSpawn(specialPos, item) then
            spawned = spawned + 1
        end
    end

    safeAudio(pos, AUDIO.WHALE_BIG, AUDIO.EXPLOSION, 2.5)
    setStatus(playerId, "✨ SPECIAL! " .. spawned .. " unique objects!")
end

-- =============================================================================
-- AWESOME EXPLOSION EFFECTS
-- =============================================================================


local function microBombCarpet(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local bombs = 0
    
    -- Create a massive carpet bombing effect with micro explosions
    -- Grid pattern for maximum coverage and visual impact
    local gridSize = 15  -- 15x15 grid
    local spacing = 3    -- 3 units apart
    local startX = pos.x - (gridSize * spacing / 2)
    local startZ = pos.z - (gridSize * spacing / 2)
    
    for x = 0, gridSize - 1 do
        for z = 0, gridSize - 1 do
            local bombPos = tm.vector3.Create(
                startX + (x * spacing),
                pos.y + math.random(8, 15),  -- Slightly elevated
                startZ + (z * spacing)
            )
            
            if safeSpawn(bombPos, PREFABS.EXPLOSION_MICRO) then
                bombs = bombs + 1
            end
            
            -- Safety limit to prevent performance issues
            if bombs >= MAX_SPAWNS_PER_ABILITY then
                break
            end
        end
        if bombs >= MAX_SPAWNS_PER_ABILITY then
            break
        end
    end
    
    safeAudio(pos, AUDIO.EXPLOSION, AUDIO.FIREWORKS, 3.0)
    setStatus(playerId, "💣 CARPET BOMBING! " .. bombs .. " micro bombs deployed!")
end

local function flamethrowerTest(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local flames = 0
    
    -- Pattern 1: Circle of flames around player (radius 8)
    for i = 0, 7 do
        local angle = (i / 8) * 2 * math.pi
        local flamePos = tm.vector3.Create(
            pos.x + math.cos(angle) * 8,
            pos.y,  -- Ground level
            pos.z + math.sin(angle) * 8
        )
        
        if safeSpawn(flamePos, "PFB_FlameThrowerEffect") then
            flames = flames + 1
        end
    end
    
    -- Pattern 2: Cross pattern through the center
    local crossPositions = {
        {6, 0}, {-6, 0}, {0, 6}, {0, -6},  -- Main cross
        {3, 0}, {-3, 0}, {0, 3}, {0, -3}   -- Inner cross
    }
    
    for _, offset in ipairs(crossPositions) do
        local flamePos = tm.vector3.Create(
            pos.x + offset[1],
            pos.y,  -- Ground level
            pos.z + offset[2]
        )
        
        if safeSpawn(flamePos, "PFB_FlameThrowerEffect") then
            flames = flames + 1
        end
    end
    
    -- Pattern 3: Center flame
    if safeSpawn(tm.vector3.Create(pos.x, pos.y, pos.z), "PFB_FlameThrowerEffect") then
        flames = flames + 1
    end
    
    safeAudio(pos, AUDIO.EXPLOSION, nil, 2.0)
    setStatus(playerId, "🔥 FLAME PATTERNS! " .. flames .. " ground flames in cross & circle!")
end




-- =============================================================================
-- NEW CUSTOM EFFECTS
-- =============================================================================

local function chirpoArmy(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local chirpos = 0
    
    -- Array of all Chirpo color variants
    local chirpoTypes = {
        PREFABS.CHIRPO_BLUE,
        PREFABS.CHIRPO_DARK,
        PREFABS.CHIRPO_LIGHTGREEN,
        PREFABS.CHIRPO_ORANGE,
        PREFABS.CHIRPO_PURPLE,
        PREFABS.CHIRPO_WHITE,
        PREFABS.CHIRPO_CAPTAIN  -- Special captain chirpo
    }
    
    -- Create a massive army of colorful Chirpos on the ground
    for i = 1, 30 do
        local chirpoPos = tm.vector3.Create(
            pos.x + math.random(-25, 25),
            pos.y,  -- At player's ground level
            pos.z + math.random(-25, 25)
        )
        
        -- Pick random Chirpo color, but favor Captain Speck (10% chance)
        local chirpoType
        if math.random() > 0.9 then
            chirpoType = PREFABS.CHIRPO_CAPTAIN  -- Special captain chirpo
        else
            chirpoType = chirpoTypes[math.random(1, #chirpoTypes - 1)]  -- Regular colors (exclude captain from random selection)
        end
        
        if safeSpawn(chirpoPos, chirpoType) then
            chirpos = chirpos + 1
        end
        
        -- Safety limit
        if chirpos >= 30 then
            break
        end
    end
    
    -- Play multiple Chirpo sounds for authentic army effect
    safeAudio(pos, AUDIO.CHIRPO_TALK, AUDIO.CHIRPO_AI, 2.5)
    safeAudio(pos, AUDIO.CHIRPO_TYPE, nil, 1.5)
    
    setStatus(playerId, "🐤 CHIRPO ARMY! " .. chirpos .. " Chirpos deployed!")
end

local function flamethrowerInferno(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local fires = 0
    
    -- Use only Ring of Fire for proper flat ground-level fire effects
    for i = 1, 20 do
        local firePos = tm.vector3.Create(
            pos.x + math.random(-25, 25),
            pos.y + 1,
            pos.z + math.random(-25, 25)
        )
        
        if safeSpawn(firePos, PREFABS.RING_OF_FIRE) then
            fires = fires + 1
        end
    end
    
    -- Add some explosions for dramatic fire bursts
    for i = 1, 10 do
        local burstPos = tm.vector3.Create(
            pos.x + math.random(-15, 15),
            pos.y + math.random(2, 6),
            pos.z + math.random(-15, 15)
        )
        
        if safeSpawn(burstPos, PREFABS.EXPLOSION_LARGE) then
            fires = fires + 1
        end
    end
    
    safeAudio(pos, AUDIO.EXPLOSION, AUDIO.FIREWORKS, 3.0)
    setStatus(playerId, "🔥 FIRE INFERNO! " .. fires .. " fire effects deployed!")
end

local function timelinePodLanding(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local pods = 0
    
    -- Spawn a single Timeline Pod on the ground near the player
    local podPos = tm.vector3.Create(
        pos.x + math.random(-10, 10),
        pos.y,  -- At player's ground level
        pos.z + math.random(-10, 10)
    )
    
    if safeSpawn(podPos, PREFABS.TIMELINE_POD) then
        pods = pods + 1
    end
    
    safeAudio(pos, AUDIO.TELEPORT, AUDIO.EXPLOSION, 2.5)
    
    if pods > 0 then
        setStatus(playerId, "🛸 TIMELINE POD! A mysterious pod has landed nearby!")
    else
        setStatus(playerId, "🛸 TIMELINE POD! Pod failed to spawn")
    end
end

local function megaShieldTrap(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local spheres = 0
    
    -- EXACT COPY of original Shield Trap code - ONLY change radius and make it taller
    local centerX = pos.x
    local centerY = pos.y -20
    local centerZ = pos.z
    local radius = 60  -- TRULY MEGA! 5x bigger than original (12)
    
    -- Generate complete sphere using spherical coordinates
    -- Accounting for shield object size - fewer, more spaced points
    -- Phi (vertical angle): 0 to pi (top to bottom)
    -- Theta (horizontal angle): 0 to 2*pi (around)
    local phiSteps = 16   -- Fewer divisions to prevent overlap
    local thetaSteps = 20 -- Fewer divisions to prevent overlap
    
    for phiIndex = 0, phiSteps do
        local phi = (phiIndex / phiSteps) * math.pi  -- 0 to pi
        
        -- Skip poles to avoid clustering - handle them separately
        if phiIndex > 0 and phiIndex < phiSteps then
            for thetaIndex = 0, thetaSteps - 1 do
                local theta = (thetaIndex / thetaSteps) * 2 * math.pi  -- 0 to 2*pi
                
                -- Convert spherical to cartesian coordinates
                local x = radius * math.sin(phi) * math.cos(theta)
                local y = radius * math.cos(phi)
                local z = radius * math.sin(phi) * math.sin(theta)
                
                local spherePos = tm.vector3.Create(
                    centerX + x,
                    centerY + y,
                    centerZ + z
                )
                
                if safeSpawn(spherePos, PREFABS.ENERGY_SHIELD) then
                    spheres = spheres + 1
                end
                
                -- Safety limit
                if spheres >= 100 then
                    break
                end
            end
        end
        
        if spheres >= 100 then
            break
        end
    end
    
    -- Add both poles manually for perfect sphere completion
    if spheres < 100 then
        -- Top pole
        local topPole = tm.vector3.Create(centerX, centerY + radius, centerZ)
        if safeSpawn(topPole, PREFABS.ENERGY_SHIELD) then
            spheres = spheres + 1
        end
        
        -- Bottom pole
        local bottomPole = tm.vector3.Create(centerX, centerY - radius, centerZ)
        if safeSpawn(bottomPole, PREFABS.ENERGY_SHIELD) then
            spheres = spheres + 1
        end
    end
    
    safeAudio(pos, AUDIO.SHIELD_ACTIVATE, AUDIO.SHIELD_PULSE, 2.5)
    setStatus(playerId, "🌐 MEGA TRAP! " .. spheres .. " shields deployed!")
end

local function stationaryChirpo(playerId)
    local pos = tm.players.GetPlayerTransform(playerId).GetPosition()
    local chirpos = 0
    
    -- Spawn a single Stationary Chirpo on the ground near the player
    local chirpoPos = tm.vector3.Create(
        pos.x + math.random(-8, 8),
        pos.y,  -- At player's ground level
        pos.z + math.random(-8, 8)
    )
    
    if safeSpawn(chirpoPos, PREFABS.CHIRPO_STATIONARY) then
        chirpos = chirpos + 1
    end
    
    safeAudio(pos, AUDIO.CHIRPO_TALK, AUDIO.CHIRPO_TYPE, 2.0)
    
    if chirpos > 0 then
        setStatus(playerId, "🤖 CHIRPO SPACESHIP! A helpful Chirpo unit has been deployed!")
    else
        setStatus(playerId, "🤖 CHIRPO SPACESHIP! Chirpo failed to spawn")
    end
end

-- Shield spawning functions

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
        setStatus(playerId, "🛡️ " .. sizeName .. " SHIELD deployed!")
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
-- PAGE SYSTEM
-- =============================================================================

-- Forward declarations
local buildPage1UI, buildPage2UI, buildPage3UI

local function switchToPage(playerId, pageNumber)
    -- Update shockwaves when switching pages too
    ShockwaveManager.update()
    ShockwaveManager.autoCleanup()  -- Check for cleanup when switching pages too
    
    playerPages[playerId] = pageNumber
    tm.playerUI.ClearUI(playerId)
    
    -- Rebuild UI for the requested page
    if pageNumber == 1 then
        buildPage1UI(playerId)
    elseif pageNumber == 2 then
        buildPage2UI(playerId)
    else
        buildPage3UI(playerId)
    end

    setStatus(playerId, "📖 Switched to Page " .. pageNumber)
end

buildPage1UI = function(playerId)
    local pid = playerId
    
    -- Title and status
    tm.playerUI.AddUILabel(pid, "title", "🎛️ === CHAOSBOARD === 🎛️")
    tm.playerUI.AddUIText(pid, "status", "Ready for chaos!", nil)
    
    -- === SHIELDS ROW ===
    tm.playerUI.AddUILabel(pid, "shields_label", "🛡️ SHIELDS:")

    tm.playerUI.AddUIButton(pid, "megapulse", "🛡️ Ground Shield", function()
        useAbility(pid, "megapulse", createMegadrillPulse)
    end)

    tm.playerUI.AddUIButton(pid, "shield_small", "🛡️ Small Sky Shield", function()
        useAbility(pid, "shield_small", spawnSmallShield)
    end)

    tm.playerUI.AddUIButton(pid, "shield_medium", "🛡️ Medium Sky Shield", function()
        useAbility(pid, "shield_medium", spawnMediumShield)
    end)

    tm.playerUI.AddUIButton(pid, "shield_large", "🛡️ Large Sky Shield", function()
        useAbility(pid, "shield_large", spawnLargeShield)
    end)

    tm.playerUI.AddUIButton(pid, "ring_show", "💫 Ring Light Show", function()
        useAbility(pid, "ring_show", ringLightShow)
    end)

    tm.playerUI.AddUIButton(pid, "rainbow_trail", "⚡ Energy Trail", function()
        useAbility(pid, "rainbow_trail", rainbowTrail)
    end)

    tm.playerUI.AddUIButton(pid, "crystal_garden", "💎 Crystal Garden", function()
        useAbility(pid, "crystal_garden", crystalGarden)
    end)

    tm.playerUI.AddUIButton(pid, "half_sphere_top", "🌙 Top Half-Sphere", function()
        useAbility(pid, "half_sphere_top", halfSphereTop)
    end)

    tm.playerUI.AddUIButton(pid, "shield_trap", "🕳️ Shield Trap", function()
        useAbility(pid, "shield_trap", shieldTrap)
    end)

    tm.playerUI.AddUIButton(pid, "mega_shield_trap", "🌐 Mega Shield Trap", function()
        useAbility(pid, "mega_shield_trap", megaShieldTrap)
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
    
    tm.playerUI.AddUIButton(pid, "chirpo_army", "🐤 Chirpo Army", function()
        useAbility(pid, "chirpo_army", chirpoArmy)
    end)
    
    tm.playerUI.AddUIButton(pid, "timeline_pod", "🛸 Timeline Pod Landing", function()
        useAbility(pid, "timeline_pod", timelinePodLanding)
    end)
    
    tm.playerUI.AddUIButton(pid, "stationary_chirpo", "🤖 Chirpo Spaceship", function()
        useAbility(pid, "stationary_chirpo", stationaryChirpo)
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
    
    tm.playerUI.AddUIButton(pid, "reset", "🔄 Reset Physics", function()
        useAbility(pid, "reset", resetPhysics)
    end)
    
    -- === CONTROLS ROW ===
    tm.playerUI.AddUILabel(pid, "control_label", "🔧 CONTROLS:")

    tm.playerUI.AddUIButton(pid, "cleanup", "🧹 Cleanup All", function()
        useAbility(pid, "cleanup", cleanupAll)
    end)

    tm.playerUI.AddUIButton(pid, "cleanup_shields", "🛡️ Cleanup Shields", function()
        useAbility(pid, "cleanup_shields", cleanupShieldsOnly)
    end)

    tm.playerUI.AddUIButton(pid, "teleport", "🌀 Teleport Party", function()
        useAbility(pid, "teleport", teleportParty)
    end)

    tm.playerUI.AddUIButton(pid, "emergency", "🆘 Emergency Teleport", function()
        useAbility(pid, "emergency", emergencyTeleport)
    end)

    -- Page navigation at bottom
    tm.playerUI.AddUILabel(pid, "page_nav", "📖 PAGE 1 / 3")
    tm.playerUI.AddUIButton(pid, "next_page", ">> Next Page", function()
        switchToPage(pid, 2)
    end)
end

buildPage2UI = function(playerId)
    local pid = playerId
    
    -- Title and status
    tm.playerUI.AddUILabel(pid, "title", "🎛️ === CHAOSBOARD === 🎛️")
    tm.playerUI.AddUIText(pid, "status", "Ready for chaos!", nil)
    
    -- === DESTRUCTION ROW ===
    tm.playerUI.AddUILabel(pid, "destruction_label", "💥 DESTRUCTION:")

    tm.playerUI.AddUIButton(pid, "barrels", "🛢️ Barrel Rain", function()
        useAbility(pid, "barrels", barrelRain)
    end)

    tm.playerUI.AddUIButton(pid, "barrel_fortress", "🏰 Barrel Fortress", function()
        useAbility(pid, "barrel_fortress", barrelFortress)
    end)

    tm.playerUI.AddUIButton(pid, "powercore_house", "🏠 PowerCore House", function()
        useAbility(pid, "powercore_house", powerCoreHouse)
    end)

    tm.playerUI.AddUIButton(pid, "fireworks", "🎆 Fireworks Show", function()
        useAbility(pid, "fireworks", fireworksShow)
    end)

    tm.playerUI.AddUIButton(pid, "mines", "💣 Mine Field", function()
        useAbility(pid, "mines", mineField)
    end)

    tm.playerUI.AddUIButton(pid, "mine_grid", "🌸 Mine Grid", function()
        useAbility(pid, "mine_grid", mineGrid)
    end)

    tm.playerUI.AddUIButton(pid, "mine_sunflower", "🌻 Mine Sunflower", function()
        useAbility(pid, "mine_sunflower", mineSunflower)
    end)

    tm.playerUI.AddUIButton(pid, "mine_chandelier", "💎 Mine Chandelier", function()
        useAbility(pid, "mine_chandelier", mineChandelier)
    end)

    tm.playerUI.AddUIButton(pid, "gravbomb", "🌍 Gravity Bomb", function()
        useAbility(pid, "gravbomb", gravityBomb)
    end)

    tm.playerUI.AddUIButton(pid, "launcher", "🚀 Launch All Vehicles", function()
        useAbility(pid, "launcher", structureLauncher)
    end)

    -- === CHAOS EFFECTS ROW ===
    tm.playerUI.AddUILabel(pid, "chaos_label", "🌪️ CHAOS EFFECTS:")
    
    tm.playerUI.AddUIButton(pid, "poison_rain", "☠️ Poison Rain", function()
        useAbility(pid, "poison_rain", poisonRain)
    end)
    
    tm.playerUI.AddUIButton(pid, "snowball_fight", "❄️ Snowball Fight", function()
        useAbility(pid, "snowball_fight", snowballFight)
    end)
    
    tm.playerUI.AddUIButton(pid, "crystal_cavern", "💎 Crystal Cavern", function()
        useAbility(pid, "crystal_cavern", crystalCavern)
    end)
    
    tm.playerUI.AddUIButton(pid, "ring_of_fire", "🔥 Ring of Fire", function()
        useAbility(pid, "ring_of_fire", ringOfFire)
    end)
    
    tm.playerUI.AddUIButton(pid, "bone_graveyard", "💀 Bone Graveyard", function()
        useAbility(pid, "bone_graveyard", boneGraveyard)
    end)
    
    tm.playerUI.AddUIButton(pid, "boulder_avalanche", "🪨 Boulder Avalanche", function()
        useAbility(pid, "boulder_avalanche", boulderAvalanche)
    end)
    
    tm.playerUI.AddUIButton(pid, "magnetic_chaos", "🌪️ Total Chaos", function()
        useAbility(pid, "magnetic_chaos", magneticChaos)
    end)
    
    tm.playerUI.AddUIButton(pid, "chaos_trap", "🎪 Chaos Trap", function()
        useAbility(pid, "chaos_trap", chaosTrap)
    end)
    
    tm.playerUI.AddUIButton(pid, "ring_shockwave", "💥 Ring Shockwave", function()
        useAbility(pid, "ring_shockwave", ringShockwave)
    end)
    
    tm.playerUI.AddUIButton(pid, "true_shockwave", "⚡ True Shockwave", function()
        useAbility(pid, "true_shockwave", trueShockwave)
    end)
    
    tm.playerUI.AddUIButton(pid, "flamethrower_inferno", "🔥 Fire Inferno", function()
        useAbility(pid, "flamethrower_inferno", flamethrowerInferno)
    end)
    
    tm.playerUI.AddUIButton(pid, "carpet_bombing", "💣 Carpet Bombing", function()
        useAbility(pid, "carpet_bombing", microBombCarpet)
    end)
    
    tm.playerUI.AddUIButton(pid, "flame_mandala", "🔥 Flame Mandala", function()
        useAbility(pid, "flame_mandala", flamethrowerTest)
    end)
    
    -- === CONTROL ROW ===
    tm.playerUI.AddUILabel(pid, "control_label", "🔧 CONTROLS:")

    tm.playerUI.AddUIButton(pid, "cleanup", "🧹 Cleanup All", function()
        useAbility(pid, "cleanup", cleanupAll)
    end)

    tm.playerUI.AddUIButton(pid, "cleanup_shields", "🛡️ Cleanup Shields", function()
        useAbility(pid, "cleanup_shields", cleanupShieldsOnly)
    end)

    tm.playerUI.AddUIButton(pid, "teleport", "🌀 Teleport Party", function()
        useAbility(pid, "teleport", teleportParty)
    end)

    tm.playerUI.AddUIButton(pid, "emergency", "🆘 Emergency Teleport", function()
        useAbility(pid, "emergency", emergencyTeleport)
    end)

    -- Development tool: Spawnable dumper (conditionally shown)
    if ENABLE_SPAWNABLE_DUMPER then
        tm.playerUI.AddUIButton(pid, "dump_spawnables", "📋 Export Spawnables", function()
            useAbility(pid, "dump_spawnables", dumpSpawnables)
        end)
    end
    
    -- Page navigation at bottom
    tm.playerUI.AddUILabel(pid, "page_nav", "📖 PAGE 2 / 3")
    tm.playerUI.AddUIButton(pid, "prev_page", "<< Previous Page", function()
        switchToPage(pid, 1)
    end)
    tm.playerUI.AddUIButton(pid, "next_page", ">> Next Page", function()
        switchToPage(pid, 3)
    end)
end

buildPage3UI = function(playerId)
    local pid = playerId

    -- Title and status
    tm.playerUI.AddUILabel(pid, "title", "🎛️ === CHAOSBOARD === 🎛️")
    tm.playerUI.AddUIText(pid, "status", "Ready for chaos!", nil)

    -- === FROZEN TRACKS DLC ROW ===
    tm.playerUI.AddUILabel(pid, "dlc_label", "❄️ FROZEN TRACKS DLC:")

    tm.playerUI.AddUIButton(pid, "spawn_buildings", "🏘️ Buildings", function()
        useAbility(pid, "spawn_buildings", spawnBuildings)
    end)

    tm.playerUI.AddUIButton(pid, "spawn_led_signs", "💡 LED Signs", function()
        useAbility(pid, "spawn_led_signs", spawnLEDSigns)
    end)

    tm.playerUI.AddUIButton(pid, "spawn_race_track", "🏁 Race Track", function()
        useAbility(pid, "spawn_race_track", spawnRaceTrack)
    end)

    tm.playerUI.AddUIButton(pid, "spawn_environment", "🌲 Environment", function()
        useAbility(pid, "spawn_environment", spawnEnvironment)
    end)

    tm.playerUI.AddUIButton(pid, "spawn_infrastructure", "🌉 Infrastructure", function()
        useAbility(pid, "spawn_infrastructure", spawnInfrastructure)
    end)

    tm.playerUI.AddUIButton(pid, "spawn_special", "✨ Special Objects", function()
        useAbility(pid, "spawn_special", spawnSpecialObjects)
    end)

    -- === CONTROLS ROW ===
    tm.playerUI.AddUILabel(pid, "control_label", "🔧 CONTROLS:")

    tm.playerUI.AddUIButton(pid, "cleanup", "🧹 Cleanup All", function()
        useAbility(pid, "cleanup", cleanupAll)
    end)

    tm.playerUI.AddUIButton(pid, "cleanup_shields", "🛡️ Cleanup Shields", function()
        useAbility(pid, "cleanup_shields", cleanupShieldsOnly)
    end)

    tm.playerUI.AddUIButton(pid, "teleport", "🌀 Teleport Party", function()
        useAbility(pid, "teleport", teleportParty)
    end)

    tm.playerUI.AddUIButton(pid, "emergency", "🆘 Emergency Teleport", function()
        useAbility(pid, "emergency", emergencyTeleport)
    end)

    -- Page navigation at bottom
    tm.playerUI.AddUILabel(pid, "page_nav", "📖 PAGE 3 / 3")
    tm.playerUI.AddUIButton(pid, "prev_page", "<< Previous Page", function()
        switchToPage(pid, 2)
    end)
end

-- =============================================================================
-- UI SETUP
-- =============================================================================

local function onPlayerJoined(p)
    local pid = p.playerId
    
    -- Initialize player to page 1
    playerPages[pid] = 1
    
    -- Build initial UI (Page 1)
    buildPage1UI(pid)
end

-- Hook the join event
tm.players.OnPlayerJoined.add(onPlayerJoined)
