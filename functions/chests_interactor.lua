local Movement = require("functions.movement")
local interactive_patterns = require("enums.interactive_patterns")
local explorer = require("data.explorer")

local ChestsInteractor = {}

-- Estados da FSM
local States = {
    IDLE = "IDLE",
    MOVING = "MOVING",
    INTERACTING = "INTERACTING",
    CHECKING_VFX = "CHECKING_VFX",
    RETURNING_TO_CHEST = "RETURNING_TO_CHEST",
    COLLECTING_ITEMS = "COLLECTING_ITEMS"
}

-- Variáveis de estado
local currentState = States.IDLE
local targetObject = nil
local interactedObjects = {}
local expiration_time = 10
local blacklist = {}
local failed_attempts = 0
local max_attempts = 10
local max_return_attempts = 10
local vfx_check_start_time = 0
local vfx_check_duration = 4
local successful_chests_opened = 0
local state_start_time = 0
local max_state_duration = 30
local max_interaction_distance = 2
local return_to_chest_start_time = 0
local collecting_items_duration = 6
local last_known_chest_position = nil
local max_chest_search_attempts = 5
local chest_search_attempts = 0

-- Funções auxiliares
local function get_player_cinders()
    return get_helltide_coin_cinders()
end

function ChestsInteractor.update_cinders()
    local current_cinders = get_helltide_coin_cinders()
    -- Adicione aqui a lógica para atualizar os cinders, se necessário
end

local function has_enough_cinders(obj_name)
    local player_cinders = get_player_cinders()
    local required_cinders = interactive_patterns[obj_name]
    
    if type(required_cinders) == "table" then
        for _, cinders in ipairs(required_cinders) do
            if player_cinders >= cinders then
                return true
            end
        end
    elseif type(required_cinders) == "number" then
        if player_cinders >= required_cinders then
            return true
        end
    end
    
    return false
end

local function isObjectInteractable(obj, interactive_patterns)
    if not obj then return false end
    local obj_name = obj:get_skin_name()
    local is_interactable = obj:is_interactable()
    return interactive_patterns[obj_name] and 
           (not interactedObjects[obj_name] or os.clock() > interactedObjects[obj_name]) and
           has_enough_cinders(obj_name) and
           is_interactable
end

local function is_blacklisted(obj)
    if not obj then return false end
    local obj_name = obj:get_skin_name()
    local obj_pos = obj:get_position()
    
    for _, blacklisted_obj in ipairs(blacklist) do
        if blacklisted_obj.name == obj_name and blacklisted_obj.position:dist_to(obj_pos) < 0.1 then
            return true
        end
    end
    
    return false
end

local function add_to_blacklist(obj)
    if not obj then return end
    local obj_name = obj:get_skin_name()
    local obj_pos = obj:get_position()

    table.insert(blacklist, {name = obj_name, position = obj_pos})
end

local function check_chest_opened()
    local actors = actors_manager.get_all_actors()
    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        if name == "Hell_Prop_Chest_Helltide_01_Client_Dyn" then
            console.print("Baú aberto com sucesso: " .. name)
            successful_chests_opened = successful_chests_opened + 1
            console.print("Total de baús abertos com sucesso: " .. successful_chests_opened)
            return true
        end
    end
    return false
end

local function resume_waypoint_movement()
    Movement.set_explorer_control(false)
    Movement.set_moving(true)
end

local function reset_state()
    targetObject = nil
    last_known_chest_position = nil
    chest_search_attempts = 0
    failed_attempts = 0
    Movement.set_interacting(false)
    explorer.disable()
    Movement.set_explorer_control(false)
    Movement.enable_anti_stuck()
    state_start_time = os.clock()
    return_to_chest_start_time = 0
    resume_waypoint_movement()
end

local function move_to_object(obj)
    if not obj then 
        if last_known_chest_position then
            explorer.set_target(last_known_chest_position)
            explorer.enable()
            Movement.set_explorer_control(true)
            Movement.disable_anti_stuck()
            chest_search_attempts = chest_search_attempts + 1
            return States.MOVING
        else
            reset_state()
            return States.IDLE
        end
    end
    local obj_pos = obj:get_position()
    last_known_chest_position = obj_pos
    explorer.set_target(obj_pos)
    explorer.enable()
    Movement.set_explorer_control(true)
    Movement.disable_anti_stuck()
    chest_search_attempts = 0
    return States.MOVING
end

local function is_player_too_far_from_target()
    if not targetObject then return true end
    local player = get_local_player()
    if not player then return true end
    
    local player_position = player:get_position()
    local target_position = targetObject:get_position()
    local distance = target_position:dist_to(player_position)
    
    return distance > max_interaction_distance
end

-- Funções de estado
local stateFunctions = {
    [States.IDLE] = function(objects, interactive_patterns)
        reset_state()
        for _, obj in ipairs(objects) do
            if isObjectInteractable(obj, interactive_patterns) and not is_blacklisted(obj) then
                targetObject = obj
                return move_to_object(obj)
            end
        end
        return States.IDLE
    end,

    [States.MOVING] = function()
        if not targetObject then
            if chest_search_attempts >= max_chest_search_attempts then
                reset_state()
                return States.IDLE
            end
            if last_known_chest_position then
                if explorer.is_target_reached() then
                    chest_search_attempts = chest_search_attempts + 1
                    if chest_search_attempts >= max_chest_search_attempts then
                        reset_state()
                        return States.IDLE
                    else
                        return move_to_object(nil)
                    end
                end
            else
                reset_state()
                return States.IDLE
            end
        elseif not isObjectInteractable(targetObject, interactive_patterns) then 
            reset_state()
            return States.IDLE 
        end
        
        if is_player_too_far_from_target() then
            return move_to_object(targetObject)
        end
        
        if explorer.is_target_reached() then
            explorer.disable()
            Movement.set_explorer_control(false)
            if targetObject and targetObject:is_interactable() then
                return States.INTERACTING
            else
                failed_attempts = failed_attempts + 1
                if failed_attempts >= max_attempts then
                    reset_state()
                    return States.IDLE
                end
                return move_to_object(targetObject)
            end
        end
        
        return States.MOVING
    end,

    [States.INTERACTING] = function()
        if not targetObject or not targetObject:is_interactable() then 
            return move_to_object(targetObject)
        end

        if is_player_too_far_from_target() then
            return move_to_object(targetObject)
        end

        Movement.set_interacting(true)
        local obj_name = targetObject:get_skin_name()
        interactedObjects[obj_name] = os.clock() + expiration_time
        interact_object(targetObject)
        vfx_check_start_time = os.clock()
        return States.CHECKING_VFX
    end,

    [States.CHECKING_VFX] = function()
        if os.clock() - vfx_check_start_time > vfx_check_duration or is_player_too_far_from_target() then
            failed_attempts = failed_attempts + 1
            if failed_attempts >= max_attempts then
                add_to_blacklist(targetObject)
                reset_state()
                return States.IDLE
            else
                Movement.set_interacting(false)
                return move_to_object(targetObject)
            end
        end

        if check_chest_opened() then
            console.print("Baú confirmado como aberto após " .. (failed_attempts + 1) .. " tentativas")
            return States.RETURNING_TO_CHEST
        end

        return States.CHECKING_VFX
    end,

    [States.RETURNING_TO_CHEST] = function()
        if not targetObject then
            reset_state()
            return States.IDLE
        end

        local player = get_local_player()
        if not player then return States.IDLE end

        local player_position = player:get_position()
        local chest_position = targetObject:get_position()
        
        if player_position:dist_to(chest_position) <= max_interaction_distance then
            console.print("Retornado ao baú, iniciando coleta de itens")
            return_to_chest_start_time = os.clock()
            return States.COLLECTING_ITEMS
        end

        failed_attempts = failed_attempts + 1
        if failed_attempts >= max_return_attempts then
            reset_state()
            return States.IDLE
        end

        explorer.set_target(chest_position)
        explorer.enable()
        Movement.set_explorer_control(true)
        return States.RETURNING_TO_CHEST
    end,

    [States.COLLECTING_ITEMS] = function()
        if os.clock() - return_to_chest_start_time >= collecting_items_duration then
            console.print("Tempo de coleta de itens concluído")
            add_to_blacklist(targetObject)
            reset_state()
            return States.IDLE
        end

        return States.COLLECTING_ITEMS
    end
}

-- Função principal de interação
function ChestsInteractor.interactWithObjects(doorsEnabled, interactive_patterns)
    local local_player = get_local_player()
    if not local_player then return end
    
    local objects = actors_manager.get_ally_actors()
    if not objects then return end
    
    if os.clock() - state_start_time > max_state_duration then
        currentState = States.IDLE
        reset_state()
    end
    
    if is_player_too_far_from_target() and currentState ~= States.IDLE then
        currentState = States.IDLE
        reset_state()
    end
    
    local newState = stateFunctions[currentState](objects, interactive_patterns)
    if newState ~= currentState then
        currentState = newState
        state_start_time = os.clock()
    end
end

-- Funções auxiliares
function ChestsInteractor.clearInteractedObjects()
    interactedObjects = {}
end

function ChestsInteractor.clearBlacklist()
    blacklist = {}
end

function ChestsInteractor.printBlacklist()
    for i, item in ipairs(blacklist) do
        local pos_string = "posição desconhecida"
        if item.position then
            pos_string = string.format("(%.2f, %.2f, %.2f)", item.position:x(), item.position:y(), item.position:z())
        end
    end
end

function ChestsInteractor.getSuccessfulChestsOpened()
    return successful_chests_opened
end

function ChestsInteractor.draw_chest_info()
    local chest_info_text = string.format("Total de Baús Helltide Abertos: %d", successful_chests_opened)
    graphics.text_2d(chest_info_text, vec2:new(10, 70), 20, color_white(255))
end

function ChestsInteractor.is_active()
    return currentState ~= States.IDLE
end

return ChestsInteractor