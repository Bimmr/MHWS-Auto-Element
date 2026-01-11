local version = "0.0.1"

-- Cached values
local sdk = sdk
local imgui = imgui
local chatManager = sdk.get_managed_singleton("app.ChatManager")

-- Configuration
local ENABLED = true

-- value corresponds to app.PlayerDef.ATTRIBUTE_TYPE
local ELEMENTS = {
    { name = "Fire",    value = 1, field = "_Fire" },
    { name = "Water",   value = 2, field = "_Water" },
    { name = "Thunder", value = 4, field = "_Thunder" },
    { name = "Ice",     value = 3, field = "_Ice" },
    { name = "Dragon",  value = 5, field = "_Dragon" }
}

-- Cache for original element value
local originalElement = nil
local currentBestElement = nil
local monsterElementCache = {}

--- Function to get best element for a specific monster part
--- @param monster userdata The monster object
--- @param partIndex number The index of the monster part
--- @return string, number The best element name and its value
local function GetElementForMonsterPart(monster, partIndex)
    
    if not monster then return nil, 0 end

    -- check cache first
    local monsterId = monster:get_EmID()
    if monsterId and monsterElementCache[monsterId] and monsterElementCache[monsterId][partIndex] then
        return monsterElementCache[monsterId][partIndex].element, monsterElementCache[monsterId][partIndex].value
    end
    
    local parts = monster:get_field("Parts")
    if not parts then return nil, 0 end

    local params = parts:get_field("_ParamParts")
    if not params then return nil, 0 end

    local meats = params:get_field("_MeatArray"):get_field("_DataArray")
    if not meats then return nil, 0 end
    
    local partsArray = params:get_field("_PartsArray"):get_field("_DataArray")
    if not partsArray then return nil, 0 end

    local part = partsArray[partIndex]
    if not part then return nil, 0 end

    local part_meat_guid = part:get_field("_MeatGuidNormal")
    if not part_meat_guid then return nil, 0 end

    local meat_nullable = params:getMeatIndex(part_meat_guid)
    if not meat_nullable or not meat_nullable:get_field("_HasValue") then return nil, 0 end
    local meat_index = meat_nullable:get_field("_Value")

    local meat = meats[meat_index]
    if not meat then return nil, 0 end

    local bestElement = nil
    local bestValue = 0
    for _, elm in ipairs(ELEMENTS) do

        local value = meat:get_field(elm.field)

        -- add to cache
        monsterElementCache[monsterId] = monsterElementCache[monsterId] or {}
        monsterElementCache[monsterId][partIndex] = monsterElementCache[monsterId][partIndex] or {}
        monsterElementCache[monsterId][partIndex].element = bestElement
        monsterElementCache[monsterId][partIndex].value = bestValue

        -- Find the best element
        if value and value > bestValue then 
            bestElement = elm.name 
            bestValue = value 
        end
    end
    
    log.debug(string.format("Regular for %s part %s: %s (%.2f)", tostring(monster:get_EmID()), partIndex, tostring(bestElement), bestValue))
    return bestElement, bestValue
end


--- Function to get player's hunter status
--- @return userdata The hunter status object
local function GetPlayerHunterStatus()
    local player_manager = sdk.get_managed_singleton("app.PlayerManager")
    if not player_manager then return nil end

    local player = player_manager:getMasterPlayerInfo()
    if not player then return nil end

    local hunter_character = player:get_Character()
    if not hunter_character then return nil end

    return hunter_character:get_HunterStatus()
end

--- Function to change weapon element, will cache original element on first change
--- @param elementName string The name of the element to change to
--- @return boolean True if successful, false otherwise
local function ChangeWeaponElement(elementName)
    local status = GetPlayerHunterStatus()
    if not status then return false end

    local attack_power = status:get_AttackPower()
    if not attack_power then return false end

    -- Get the element type enum value
    local elementValue = nil
    for _, elem in ipairs(ELEMENTS) do
        if elem.name == elementName then
            elementValue = elem.value
            break
        end
    end
    if not elementValue then return false end

    -- Cache original element value on first change
    if originalElement == nil then
        originalElement = attack_power:get_field("_WeaponAttrType")
    end

    -- Set the new element
    attack_power:set_field("_WeaponAttrType", elementValue)
    currentBestElement = elementName

    return true
end

--- Function to restore original element
local function RestoreOriginalElement()
    if originalElement == nil then return end

    local status = GetPlayerHunterStatus()
    if not status then return end

    local attack_power = status:get_AttackPower()
    if not attack_power then return end

    attack_power:set_field("_WeaponAttrType", originalElement)
    log.debug("Restored original element: " .. tostring(originalElement))

    originalElement = nil
    currentBestElement = nil
end

-- Hook into hit processing to detect monster hits
local last_hit = {}
sdk.hook(sdk.find_type_definition("app.HunterCharacter"):get_method("evHit_AttackPreProcess(app.HitInfo)"),
    function(args)
        local hunter = sdk.to_managed_object(args[2])
        if not hunter:get_type_definition():is_a("app.HunterCharacter") then return end
        if not hunter:get_IsMaster() then return end

        local hit_info = sdk.to_managed_object(args[3])

        local damage_data = hit_info:get_DamageData()
        if not damage_data then return end
        local success, hit_part = pcall(function() return damage_data:get_PartsIndex() end)
        if not success or not hit_part then return end

        local damage_owner = hit_info:get_DamageOwner()
        if not damage_owner then return end

        local damage_owner_address = damage_owner:get_address()
        if damage_owner_address == last_hit.address and hit_part == last_hit.part then 
            log.debug("Skipping duplicate hit processing")
            return end
        log.debug(string.format("Processing hit on monster part %s", tostring(hit_part)))

        local monster_comp = damage_owner:call("getComponent(System.Type)", sdk.typeof("app.EnemyBossCharacter"))
        if not monster_comp then return end

        local monster = monster_comp:get_field("_Context")
        monster = monster:get_Em()
       
        if monster then
            local bestElement, bestValue = GetElementForMonsterPart(monster, hit_part)
            if bestElement then
                if bestElement ~= currentBestElement then
                    if ChangeWeaponElement(bestElement) then
                        log.debug(string.format("Changed weapon element to %s (%.2f) for monster %s part %s", bestElement, bestValue, tostring(monster:get_EmID()), tostring(hit_part)))
                        last_hit.address = damage_owner_address
                        last_hit.part = hit_part
                    end
                end
            end
        end
    end)

--- Function to reset element changes and hit cache
local function reset()
    RestoreOriginalElement()
    last_hit = {}
end

-- Restore original element when changing weapons
sdk.hook(sdk.find_type_definition("app.HunterCharacter"):get_method("changeWeapon"), function(args)
    local managed = sdk.to_managed_object(args[2])
    if not managed:get_type_definition():is_a("app.HunterCharacter") then return end
    if not managed:get_IsMaster() then return end
    reset()
end)

-- Restore original element on weapon swap from reserve
sdk.hook(sdk.find_type_definition("app.HunterCharacter"):get_method("changeWeaponFromReserve"), function(args)
    local managed = sdk.to_managed_object(args[2])
    if not managed:get_type_definition():is_a("app.HunterCharacter") then return end
    if not managed:get_IsMaster() then return end
    reset()
end)

-- Restore original element on script reset
re.on_script_reset(function()
    reset()
end)

-- On REFramework draw UI
re.on_draw_ui(function()
    if imgui.collapsing_header("Auto Element") then
 
        imgui.push_style_var(12, 5.0) -- Rounded elements
        imgui.push_id("auto_element")
        imgui.indent(10)

        local changed, value = false, nil

        changed, ENABLED = imgui.checkbox("Enabled", ENABLED)

        imgui.spacing()
        imgui.unindent(10)
        imgui.pop_id()
        imgui.pop_style_var() -- Rounded elements
    end
end)
