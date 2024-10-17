local explorer = require("data.explorer")
local circular_movement = {}

-- Circular Movement Variables
local run_explorer = 0
local explorer_points = nil
local explorer_point = nil
local explorer_go_next = 1
local explorer_threshold = 1.5
local explorer_thresholdvar = 3.0
local last_explorer_threshold_check = 0
local explorer_circle_radius_prev = 0

-- Movement variables
local movement_paused = false
local movement_activated = false

-- Nova função para verificar se o boss está vivo
local function is_boss_alive(actor)
    if actor.is_dead and actor:is_dead() then
        return false
    end
    
    if actor.get_current_health then
        local health = actor:get_current_health()
        return health and health > 0
    end
    
    -- Se não pudermos determinar com certeza, assumimos que está vivo
    return true
end

-- Função auxiliar para obter posições em um raio
local function get_positions_in_radius(center_point, radius)
    local positions = {}
    local radius_squared = radius * radius
    for x = -radius, radius do
        for y = -radius, radius do
            if x*x + y*y <= radius_squared then
                table.insert(positions, vec3:new(center_point:x() + x, center_point:y() + y, center_point:z()))
            end
        end
    end
    return positions
end

-- Sort a element in a table
local function random_element(tb)
    return tb[math.random(#tb)]
end

-- Func to pause mov
function circular_movement.pause_movement()
    movement_paused = true
end

-- Func to resume mov
function circular_movement.resume_movement()
    movement_paused = false
end

-- Func to check if player is near maiden
function circular_movement.is_near_maiden(player_position, maiden_position, radius)
    return player_position:dist_to(maiden_position) <= radius * 1.2
end

-- Func to check if player is outside circle
function circular_movement.is_player_outside_circle(player_position, circle_center, radius)
    local distance = player_position:dist_to(circle_center)
    return distance > radius
end

-- Nova função para verificar e mover para o boss
local function check_and_move_to_boss()
    local actors = actors_manager.get_all_actors()
    if not actors or #actors == 0 then
        console.print("Nenhum ator encontrado.")
        return false
    end

    local local_player = get_local_player()
    if not local_player then
        console.print("Jogador local não encontrado.")
        return false
    end

    local player_position = local_player:get_position()
    if not player_position then
        console.print("Posição do jogador não encontrada.")
        return false
    end
    
    console.print("Procurando pelo boss entre " .. #actors .. " atores.")

    -- Procurando pelo boss
    for _, actor in ipairs(actors) do
        if actor and actor.is_enemy and actor.get_skin_name then
            local skin_name = actor:get_skin_name()
            if actor:is_enemy() and is_boss_alive(actor) and skin_name == "S04_demon_succubus_miniboss" then
                console.print("Boss encontrado! Nome da skin: " .. skin_name)
                local boss_position = actor:get_position()
                if boss_position then
                    console.print("Posição do boss: x=" .. boss_position:x() .. ", y=" .. boss_position:y() .. ", z=" .. boss_position:z())
                    console.print("Definindo alvo do explorer para a posição do boss.")
                    explorer.set_target(boss_position)
                    explorer.enable()
                    pathfinder.clear_stored_path()
                    
                    -- Verificação adicional
                    local explorer_target = explorer.get_target()
                    if explorer_target then
                        console.print("Alvo do explorer definido para: x=" .. explorer_target:x() .. ", y=" .. explorer_target:y() .. ", z=" .. explorer_target:z())
                    else
                        console.print("Falha ao definir o alvo do explorer.")
                    end
                    
                    return true
                else
                    console.print("Posição do boss não encontrada.")
                end
            end
        end
    end
    
    console.print("Boss não encontrado.")
    return false
end

-- Main func circ mov
function circular_movement.update(menu_elements, helltide_final_maidenpos, explorer_circle_radius)
    local current_time = os.clock()
    local local_player = get_local_player()
    if not local_player then
        return
    end

    if not menu_elements.main_helltide_maiden_auto_plugin_enabled:get() then
        return
    end

    -- Verify if mov is paused
    if movement_paused then
        return
    end

    -- Verificar e mover para o boss, se encontrado
    if check_and_move_to_boss() then
        return
    end

    local player_position = local_player:get_position()

    -- Verify if player is near maiden to start circ mov
    if circular_movement.is_near_maiden(player_position, helltide_final_maidenpos, explorer_circle_radius) then
        movement_activated = true
    end

    -- Verify if player is outside circle after movement was activated
    if movement_activated and circular_movement.is_player_outside_circle(player_position, helltide_final_maidenpos, explorer_circle_radius) then
        console.print("Jogador saiu do círculo! Retornando ao centro.")
        explorer.set_target(helltide_final_maidenpos)
        explorer.enable()
        pathfinder.clear_stored_path()
        return
    end

    if menu_elements.main_helltide_maiden_auto_plugin_run_explorer:get() and helltide_final_maidenpos then
        run_explorer = 1
        
        if not explorer_points or explorer_circle_radius_prev ~= explorer_circle_radius then
            explorer_circle_radius_prev = explorer_circle_radius
            explorer_points = get_positions_in_radius(helltide_final_maidenpos, explorer_circle_radius)
        end

        if explorer_points then
            if explorer_go_next == 1 then
                if current_time - last_explorer_threshold_check < explorer_threshold then
                    return
                end
                last_explorer_threshold_check = current_time

                local random_waypoint = random_element(explorer_points)
                random_waypoint = utility.set_height_of_valid_position(random_waypoint)
                if utility.is_point_walkeable_heavy(random_waypoint) then
                    explorer_point = random_waypoint
                    
                    explorer_threshold = menu_elements.main_helltide_maiden_auto_plugin_explorer_threshold:get()
                    explorer_thresholdvar = math.random(0, menu_elements.main_helltide_maiden_auto_plugin_explorer_thresholdvar:get())
                    explorer_threshold = explorer_threshold + explorer_thresholdvar

                    pathfinder.force_move_raw(explorer_point)
                    explorer_go_next = 0
                end
            else
                if explorer_point and not explorer_point:is_zero() then
                    if player_position:dist_to(explorer_point) < 2.5 then
                        explorer_go_next = 1
                    else
                        pathfinder.force_move_raw(explorer_point)
                    end
                end
            end
        end
    else
        run_explorer = 0
        pathfinder.clear_stored_path()
    end
end

-- Clear blacklist (if necessary)
function circular_movement.clearBlacklist()
    -- blacklist logic in case
end

return circular_movement