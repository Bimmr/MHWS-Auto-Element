local version = "0.0.1"

-- Cached values
local sdk = sdk
local imgui = imgui
local chatManager = sdk.get_managed_singleton("app.ChatManager")


-- Other required files
local config = require("AutoElement.Config")
local bindings = require("AutoElement.Bindings")


-- Cache for original element value
local element_original = nil
local element_set = nil
local monster_element_cache = {}
local last_hit = {}


-- Remember if the current weapon has an element, used to skip hook early if ONLY_ADD_IF_ELEMENTAL is true
local current_weapon_has_element = true -- Assume true initially, this will be updated on first change attempt


-- Configuration
local ENABLED = true
local PER_PART = true
local ONLY_ADD_IF_ELEMENTAL = false


-- Element definitions
local ELEMENTS = {
    { name = "Fire",    value = 1, field = "_Fire" },
    { name = "Water",   value = 2, field = "_Water" },
    { name = "Thunder", value = 4, field = "_Thunder" },
    { name = "Ice",     value = 3, field = "_Ice" },
    { name = "Dragon",  value = 5, field = "_Dragon" }
}


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
    local element_value = nil
    for _, elem in ipairs(ELEMENTS) do
        if elem.name == elementName then
            element_value = elem.value
            break
        end
    end
    if not element_value then return false end

    local current_attr = attack_power:get_field("_WeaponAttrType")

    -- Check if weapon has elemental attribute. If it doesn't then we require ONLY_ADD_IF_ELEMENTAL to be true before we set the new element
    if ONLY_ADD_IF_ELEMENTAL and (current_attr == 0 or current_attr == nil) then
        current_weapon_has_element = false
        return false
    end

    -- Cache original element value on first change
    if element_original == nil then
        element_original = current_attr
    end

    -- Set the new element
    attack_power:set_field("_WeaponAttrType", element_value)
    element_set = elementName

    return true
end

--- Function to restore original element
local function RestoreOriginalElement()
    if element_original == nil then return end

    local status = GetPlayerHunterStatus()
    if not status then return end

    local attack_power = status:get_AttackPower()
    if not attack_power then return end

    attack_power:set_field("_WeaponAttrType", element_original)
    log.debug("Restored original element: " .. tostring(element_original))

    element_original = nil
    element_set = nil
end


--- Function to reset element changes, hit cache, and weapon element flag
local function reset()
    RestoreOriginalElement()
    last_hit = {}
    current_weapon_has_element = true
end

--- Function to toggle the Auto Element feature
local function toggle(new_value)
    ENABLED = new_value ~= nil and new_value or not ENABLED
    chatManager:addSystemLog(ENABLED and "Auto Element Enabled" or "Auto Element Disabled")
    config.set("Enabled.Value", ENABLED)
    if not ENABLED then
        reset()
    end
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

-- On REFramework update
re.on_frame(function()
    -- Update the bindings
    bindings.update()
end)

--------------------------------------- Config ------------------------------------
ENABLED = config.get("Enabled.Value") or ENABLED
PER_PART = config.get("Per Part") or PER_PART
ONLY_ADD_IF_ELEMENTAL = config.get("Only Change If Elemental") or ONLY_ADD_IF_ELEMENTAL

local binding_config = config.get("Enabled.Toggle")
if binding_config then
    bindings.add(binding_config.device, binding_config.input, toggle)
end


------------------------------- UI ------------------------------------
re.on_draw_ui(function()
    if imgui.collapsing_header("Auto Element") then
 
        imgui.push_style_var(12, 5.0) -- Rounded elements
        imgui.push_id("auto_element")
        imgui.indent(10)

        -- Create the binding listener
        local listen = bindings.listener:create("auto_element_listener")

        -- On listener complete set the new hotkeys
        listen:on_complete(function()
            -- Remove the old binding
            if binding_config ~= nil then
                bindings.remove(binding_config.device, binding_config.hotkeys)
            end

            -- Set the new binding
            binding_config = {
                hotkeys = listen:get_inputs(),
                device = listen:get_device()
            }

            -- Add the new binding, and save it to the config
            bindings.add(binding_config.device, binding_config.hotkeys, toggle)
            config.set("Enabled.Toggle", binding_config)
        end)

        -- Create the hotkey string
        local hotkey_string = ""

        if listen:is_listening() then
            log.debug("Listening for hotkey input...")
            -- If listening, and inputs have been started - display the hotkeys being pressed
            if #listen:get_inputs() ~= 0 then
                local inputs = listen:get_inputs()
                inputs = bindings.get_names(listen:get_device(), inputs)
                for _, input in ipairs(inputs) do
                    hotkey_string = hotkey_string .. input.name .. " + "
                end
            else
                -- If listening, but no inputs have been started - display listening
                hotkey_string = "Listening... "
            end
            -- If not listening, display the hotkeys from the config
        elseif binding_config == nil or binding_config.hotkeys == nil then
            hotkey_string = "Not Set"
        else
            local inputs = bindings.get_names(binding_config.device, binding_config.hotkeys)
            for i, input in ipairs(inputs) do
                hotkey_string = hotkey_string .. input.name
                if i < #inputs then
                    hotkey_string = hotkey_string .. " + "
                end
            end
        end
        
        local changed, ENABLED = imgui.checkbox("Enabled   ", ENABLED)
        if changed then toggle() end
        imgui.same_line()

        imgui.begin_disabled()
        imgui.set_next_item_width(200)
        imgui.input_text("", hotkey_string)
        imgui.end_disabled()
        imgui.same_line()

        -- When the change hotkey button is pressed, start listening for a new hotkey
        if imgui.button("Change Hotkey") then
            listen:start()
        end
        if imgui.is_item_hovered() then
            imgui.set_tooltip("  " .. "Supports both keyboard and controller." .. "  ")
        end

        local changed = false

        changed, PER_PART = imgui.checkbox("Change element per part", PER_PART)
        if changed then
            config.set("Per Part", PER_PART)
        end
        changed, ONLY_ADD_IF_ELEMENTAL = imgui.checkbox("Only Change If Elemental", ONLY_ADD_IF_ELEMENTAL)
        if changed then
            config.set("Only Change If Elemental", ONLY_ADD_IF_ELEMENTAL)
        end
        
        imgui.spacing()
        imgui.unindent(10)
        imgui.pop_id()
        imgui.pop_style_var() -- Rounded elements
        imgui.separator()
    end
end)




--- Function to get best elements for all monster parts
--- @param monster userdata The monster object
--- @return table A table where keys are part indices of {element = string, value = number}
local function GetAllElementsForMonster(monster)
    if not monster then return {} end

    -- Check cache first
    local monster_id = monster:get_EmID()
    if monster_id and monster_element_cache[monster_id] then
        return monster_element_cache[monster_id]
    end

    -- Retrieve necessary fields
    local parts = monster:get_field("Parts")
    if not parts then return {} end

    local params = parts:get_field("_ParamParts")
    if not params then return {} end

    local meats = params:get_field("_MeatArray"):get_field("_DataArray")
    if not meats then return {} end

    local parts_array = params:get_field("_PartsArray"):get_field("_DataArray")
    if not parts_array then return {} end

    -- Initialize results table
    local results = {}

    -- Iterate over all parts in partsArray (assuming 0-based indexing)
    local parts_count = parts_array:get_size()
    for parts_index = 0, parts_count - 1 do
        local part = parts_array[parts_index]
        if not part then 
            results[parts_index] = { best = { element = nil, value = 0 }, elements = {} }
        else
            local part_meat_guid = part:get_field("_MeatGuidNormal")
            if not part_meat_guid then 
                results[parts_index] = { best = { element = nil, value = 0 }, elements = {} }
            else
                local meat_nullable = params:getMeatIndex(part_meat_guid)
                if not meat_nullable or not meat_nullable:get_field("_HasValue") then 
                    results[parts_index] = { best = { element = nil, value = 0 }, elements = {} }
                else
                    local meat_index = meat_nullable:get_field("_Value")
                    local meat = meats[meat_index]
                    if not meat then 
                        results[parts_index] = { best = { element = nil, value = 0 }, elements = {} }
                    else
                        local best_element = nil
                        local best_value = 0
                        local all_elements = {}
                        for _, elm in ipairs(ELEMENTS) do
                            local value = meat:get_field(elm.field)
                            all_elements[elm.name] = value or 0
                            if value and value > best_value then 
                                best_element = elm.name 
                                best_value = value 
                            end
                        end
                        results[parts_index] = { best = { element = best_element, value = best_value }, elements = all_elements }
                    end
                end
            end
        end
    end

    -- Cache the full results for this monster
    monster_element_cache[monster_id] = results

    return results
end

--- Function to get best element for a specific monster part
--- @param monster userdata The monster object
--- @param partIndex number The index of the monster part
--- @return string, number The best element name and its value
local function GetElementForMonsterPart(monster, part_index)
    
    if not monster then return nil, 0 end

    -- GetAllElementsForMonster handles caching internally
    local results = GetAllElementsForMonster(monster)
    
    -- Check if the part exists in results
    if results[part_index] and results[part_index].best then
        return results[part_index].best.element, results[part_index].best.value
    end
    
    return nil, 0
end

--- Function to get best element for the entire monster
--- @param monster userdata The monster object
--- @return string, number The best element name and its value
local function GetBestElementForMonster(monster)
    if not monster then return nil, 0 end

    local monster_id = monster:get_EmID()

    -- Check cache first
    if monster_id and monster_element_cache[monster_id] and monster_element_cache[monster_id]["best"] then
        return monster_element_cache[monster_id]["best"].element, monster_element_cache[monster_id]["best"].value
    end

    local all_elements = GetAllElementsForMonster(monster)
    local element_totals = {}
    
    -- Sum all element values across all parts
    for _, part_data in pairs(all_elements) do
        if part_data.elements then
            for elem_name, elem_value in pairs(part_data.elements) do
                element_totals[elem_name] = (element_totals[elem_name] or 0) + elem_value
            end
        end
    end
    
    -- Find the element with the highest total
    local best_element = nil
    local best_value = 0
    for elem_name, total in pairs(element_totals) do
        if total > best_value then
            best_value = total
            best_element = elem_name
        end
    end

    -- Cache the best element for this monster
    monster_element_cache[monster_id] = monster_element_cache[monster_id] or {}
    monster_element_cache[monster_id]["best"] = { element = best_element, value = best_value }

    return best_element, best_value
end

-- Hook into hit processing to detect monster hits
sdk.hook(sdk.find_type_definition("app.HunterCharacter"):get_method("evHit_AttackPreProcess(app.HitInfo)"),
    function(args)

        if not ENABLED then return end -- Early out if not enabled
        if not current_weapon_has_element and ONLY_ADD_IF_ELEMENTAL then return end -- Early out if weapon has no element and we only want to add if elemental

        local hunter = sdk.to_managed_object(args[2])
        if not hunter:get_type_definition():is_a("app.HunterCharacter") then return end
        if not hunter:get_IsMaster() then return end

        local hit_info = sdk.to_managed_object(args[3])

        -- Get the damage data, we need to pcall since sometimes get_PartsIndex doesn't exist
        local damage_data = hit_info:get_DamageData()
        if not damage_data then return end
        local success, hit_part = pcall(function() return damage_data:get_PartsIndex() end)
        if not success or not hit_part then return end

        -- Get the damage owner (the monster)
        local damage_owner = hit_info:get_DamageOwner()
        if not damage_owner then return end

        -- Avoid processing the same hit multiple times
        local damage_owner_address = damage_owner:get_address()
        if damage_owner_address == last_hit.address and hit_part == last_hit.part then return end

        last_hit.address = damage_owner_address
        last_hit.part = hit_part

        -- Get the monster component from the damage owner
        local monster_comp = damage_owner:call("getComponent(System.Type)", sdk.typeof("app.EnemyBossCharacter"))
        if not monster_comp then return end

        -- Get the monster entity
        local monster = monster_comp:get_field("_Context")
        monster = monster:get_Em()
       
        if monster then

            -- Determine best element based on configuration
            local best_element, best_value = nil, 0
            if PER_PART then
                best_element, best_value = GetElementForMonsterPart(monster, hit_part)
            else
                best_element, best_value = GetBestElementForMonster(monster)
            end

            -- Change weapon element if different from current
            if best_element ~= element_set then
                if ChangeWeaponElement(best_element) then
                    log.debug(string.format("Changed weapon element to %s (%.2f) for monster %s part %s", best_element, best_value, tostring(monster:get_EmID()), tostring(hit_part)))
                end
            end
        end
    end)
