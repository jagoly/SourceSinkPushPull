-- SSPP by jagoly

main = {}

require("main.station")
require("main.hauler")

--------------------------------------------------------------------------------

local function on_entity_built(event)
    local entity = event.entity or event.created_entity ---@type LuaEntity

    local name, ghost_unit_number = entity.name, nil
    if name == "entity-ghost" then
        local tags = entity.tags or {}
        tags.ghost_unit_number = entity.unit_number
        entity.tags = tags
        name = entity.ghost_name
    else
        ghost_unit_number = event.tags and event.tags.ghost_unit_number
    end

    if name == "sspp-stop" then
        main.stop_built(entity, ghost_unit_number)
    elseif name == "sspp-general-io" or name == "sspp-provide-io" or name == "sspp-request-io" then
        main.comb_built(entity, ghost_unit_number)
    end
end

local function on_entity_broken(event)
    local entity = event.entity or event.ghost ---@type LuaEntity

    local name = entity.name
    if name == "entity-ghost" then name = entity.ghost_name end

    if name == "sspp-stop" then
        main.stop_broken(entity.unit_number, entity)
    elseif name == "sspp-general-io" or name == "sspp-provide-io" or name == "sspp-request-io" then
        main.comb_broken(entity.unit_number, entity)
    elseif entity.train then
        main.train_broken(entity.train.id, nil)
    end
end

---@param event EventData.on_player_rotated_entity
local function on_entity_rotated(event)
    local entity = event.entity

    local name = entity.name
    if name == "entity-ghost" then name = entity.ghost_name end

    if name == "sspp-general-io" or name == "sspp-provide-io" or name == "sspp-request-io" then
        -- TODO: find a way to do reverse rotate
        entity.direction = (entity.direction - 4) % 16
    end
end

--------------------------------------------------------------------------------

---@param event EventData.on_train_changed_state
local function on_train_changed_state(event)
    local train = event.train

    local state, old_state = train.state, event.old_state
    local is_manual = state == defines.train_state.manual_control or state == defines.train_state.manual_control_stop
    local was_manual = old_state == defines.train_state.manual_control or old_state == defines.train_state.manual_control_stop
    if is_manual and was_manual then return end

    if is_manual or was_manual then
        gui.hauler_set_widget_enabled(train.id, is_manual)
    end

    local hauler = storage.haulers[train.id]
    if not hauler then return end

    if is_manual then
        main.hauler_set_to_manual(hauler)
        return
    end

    if was_manual then
        main.hauler_set_to_automatic(hauler)
        return
    end

    if state == defines.train_state.no_path or state == defines.train_state.destination_full then
        set_hauler_status(hauler, { "sspp-alert.path-broken" })
        send_alert_for_train(train, hauler.status)
        train.manual_mode = true
        return
    end

    if hauler.to_provide then
        if hauler.to_provide.phase == "TRAVEL" then
            if state == defines.train_state.wait_station and train.station ~= nil then
                main.hauler_arrived_at_provide_station(hauler)
            end
        elseif hauler.to_provide.phase == "TRANSFER" then
            if state == defines.train_state.arrive_station then
                main.hauler_done_at_provide_station(hauler)
            end
        end
        return
    end

    if hauler.to_request then
        if hauler.to_request.phase == "TRAVEL" then
            if state == defines.train_state.wait_station and train.station ~= nil then
                main.hauler_arrived_at_request_station(hauler)
            end
        elseif hauler.to_request.phase == "TRANSFER" then
            if state == defines.train_state.arrive_station then
                main.hauler_done_at_request_station(hauler)
            end
        end
        return
    end

    if hauler.to_fuel then
        if hauler.to_fuel == "TRAVEL" then
            if state == defines.train_state.wait_station then
                main.hauler_arrived_at_fuel_stop(hauler)
            end
        elseif hauler.to_fuel == "TRANSFER" then
            if state == defines.train_state.arrive_station then
                main.hauler_done_at_fuel_stop(hauler)
            end
        end
        return
    end

    if hauler.to_depot then
        if state == defines.train_state.wait_station then
            main.hauler_arrived_at_depot_stop(hauler)
        end
        return
    end
end

---@param event EventData.on_train_created
local function on_train_created(event)
    if event.old_train_id_1 then
        main.train_broken(event.old_train_id_1, event.train)
    end
    if event.old_train_id_2 then
        main.train_broken(event.old_train_id_2, event.train)
    end
end

---@param event EventData.on_train_schedule_changed
local function on_train_schedule_changed(event)
    if not event.player_index then return end

    local train = event.train
    if train.manual_mode then return end

    local hauler = storage.haulers[train.id]
    if not hauler then return end

    set_hauler_status(hauler, { "sspp-alert.schedule-modified" })
    send_alert_for_train(train, hauler.status)
    train.manual_mode = true
end

--------------------------------------------------------------------------------

---@param event EventData.on_surface_created|EventData.on_surface_imported
local function on_surface_created(event)
    local surface = assert(game.get_surface(event.surface_index))
    init_network(surface)
end

---@param event EventData.on_pre_surface_cleared|EventData.on_pre_surface_deleted
local function on_surface_cleared(event)
    local surface = assert(game.get_surface(event.surface_index))

    for _, entity in pairs(surface.find_entities()) do
        local name = entity.name
        if name == "entity-ghost" then name = entity.ghost_name end

        if name == "sspp-stop" then
            main.stop_broken(entity.unit_number, entity)
        elseif name == "sspp-general-io" or name == "sspp-provide-io" or name == "sspp-request-io" then
            main.comb_broken(entity.unit_number, entity)
        end
    end

    storage.networks[surface.name] = nil
end

---@param event EventData.on_surface_renamed
local function on_surface_renamed(event)
    assert(false, "TODO: rename surface")
end

--------------------------------------------------------------------------------

---@param event EventData.on_runtime_mod_setting_changed
local function on_mod_setting_changed(event)
    populate_mod_settings()
end

local function on_init()
    init_storage()
    for _, surface in pairs(game.surfaces) do
        init_network(surface)
    end
end

local function on_load()
    --- TODO: setup mod compatibility
end

--------------------------------------------------------------------------------

local filter_built = {
    { filter = "name", name = "sspp-stop" },
    { filter = "name", name = "sspp-general-io" },
    { filter = "name", name = "sspp-provide-io" },
    { filter = "name", name = "sspp-request-io" },
    { filter = "ghost_name", name = "sspp-stop" },
    { filter = "ghost_name", name = "sspp-general-io" },
    { filter = "ghost_name", name = "sspp-provide-io" },
    { filter = "ghost_name", name = "sspp-request-io" },
}
local filter_broken = {
    { filter = "name", name = "sspp-stop" },
    { filter = "name", name = "sspp-general-io" },
    { filter = "name", name = "sspp-provide-io" },
    { filter = "name", name = "sspp-request-io" },
    { filter = "ghost_name", name = "sspp-stop" },
    { filter = "ghost_name", name = "sspp-general-io" },
    { filter = "ghost_name", name = "sspp-provide-io" },
    { filter = "ghost_name", name = "sspp-request-io" },
    { filter = "rolling-stock" },
}
local filter_ghost_broken = {
    { filter = "name", name = "sspp-stop" },
    { filter = "name", name = "sspp-general-io" },
    { filter = "name", name = "sspp-provide-io" },
    { filter = "name", name = "sspp-request-io" },
}

--------------------------------------------------------------------------------

populate_mod_settings()

script.on_event(defines.events.on_built_entity, on_entity_built, filter_built)
script.on_event(defines.events.on_entity_cloned, on_entity_built, filter_built)
script.on_event(defines.events.on_robot_built_entity, on_entity_built, filter_built)
script.on_event(defines.events.script_raised_built, on_entity_built, filter_built)
script.on_event(defines.events.script_raised_revive, on_entity_built, filter_built)

script.on_event(defines.events.on_entity_died, on_entity_broken, filter_broken)
script.on_event(defines.events.on_pre_player_mined_item, on_entity_broken, filter_broken)
script.on_event(defines.events.on_robot_pre_mined, on_entity_broken, filter_broken)
script.on_event(defines.events.script_raised_destroy, on_entity_broken, filter_broken)
script.on_event(defines.events.on_pre_ghost_deconstructed, on_entity_broken, filter_ghost_broken)

script.on_event(defines.events.on_player_rotated_entity, on_entity_rotated)

script.on_event(defines.events.on_train_changed_state, on_train_changed_state)
script.on_event(defines.events.on_train_created, on_train_created)
script.on_event(defines.events.on_train_schedule_changed, on_train_schedule_changed)

script.on_event(defines.events.on_surface_created, on_surface_created)
script.on_event(defines.events.on_surface_imported, on_surface_created)
script.on_event(defines.events.on_pre_surface_cleared, on_surface_cleared)
script.on_event(defines.events.on_pre_surface_deleted, on_surface_cleared)
script.on_event(defines.events.on_surface_renamed, on_surface_renamed)

script.on_event(defines.events.on_runtime_mod_setting_changed, on_mod_setting_changed)

script.on_event(defines.events.on_tick, on_tick)

gui.register_event_handlers()

script.on_init(on_init)
script.on_load(on_load)

script.on_configuration_changed(on_config_changed)
