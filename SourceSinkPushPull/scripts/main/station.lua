-- SSPP by jagoly

--------------------------------------------------------------------------------

---@param stop LuaEntity
---@return uint[], LuaEntity[]
local function find_nearby_combs(stop)
    local entities, x, y = storage.entities, stop.position.x, stop.position.y
    local i, comb_ids, combs = 0, {}, {}
    for _, entity in pairs(stop.surface.find_entities({ { x - 2.6, y - 2.6 }, { x + 2.6, y + 2.6 } })) do
        local unit_number = entity.unit_number
        if entities[unit_number] then
            local name = entity.name
            if name == "entity-ghost" then name = entity.ghost_name end
            if name == "sspp-general-io" or name == "sspp-provide-io" or name == "sspp-request-io" then
                i = i + 1
                comb_ids[i], combs[i] = unit_number, entity
            end
        end
    end
    return comb_ids, combs
end

---@param comb LuaEntity
---@return uint[], LuaEntity[]
local function find_nearby_stops(comb)
    local entities, x, y = storage.entities, comb.position.x, comb.position.y
    local i, stop_ids, stops = 0, {}, {}
    for _, entity in pairs(comb.surface.find_entities({ { x - 2.1, y - 2.1 }, { x + 2.1, y + 2.1 } })) do
        local unit_number = entity.unit_number
        if entities[unit_number] then
            local name = entity.name
            if name == "entity-ghost" then name = entity.ghost_name end
            if name == "sspp-stop" then
                i = i + 1
                stop_ids[i], stops[i] = unit_number, entity
            end
        end
    end
    return stop_ids, stops
end

--------------------------------------------------------------------------------

---@param stop LuaEntity
---@param combs LuaEntity[]
local function try_create_station(stop, combs)
    if stop.name == "entity-ghost" then return end

    local station_id = stop.unit_number ---@type StationId
    assert(storage.stations[station_id] == nil)

    local combs_by_name = {} ---@type {[string]: LuaEntity?}

    for _, comb in pairs(combs) do
        if #storage.comb_stop_ids[comb.unit_number] ~= 1 then return end

        local name = comb.name
        if name == "entity-ghost" or combs_by_name[name] then return end

        combs_by_name[name] = comb
    end

    local general_io = combs_by_name["sspp-general-io"]
    if not general_io then return end

    local provide_io = combs_by_name["sspp-provide-io"]
    local request_io = combs_by_name["sspp-request-io"]
    if not (provide_io or request_io) then return end

    local station = { network = stop.surface.name, stop = stop, general_io = general_io, total_deliveries = 0 } ---@type Station

    if provide_io then
        local stop_connector = stop.get_wire_connector(defines.wire_connector_id.circuit_red, true)
        local io_connector = provide_io.get_wire_connector(defines.wire_connector_id.combinator_input_red, true)
        stop_connector.connect_to(io_connector, true)

        station.provide_io = provide_io
        station.provide_items = combinator_description_to_provide_items(provide_io)
        station.provide_deliveries = {}
        station.provide_hidden_combs = {}

        ensure_hidden_combs(station.provide_io, station.provide_hidden_combs, station.provide_items)
    end

    if request_io then
        local stop_connector = stop.get_wire_connector(defines.wire_connector_id.circuit_green, true)
        local io_connector = request_io.get_wire_connector(defines.wire_connector_id.combinator_input_green, true)
        stop_connector.connect_to(io_connector, true)

        station.request_io = request_io
        station.request_items = combinator_description_to_request_items(request_io)
        station.request_deliveries = {}
        station.request_hidden_combs = {}

        ensure_hidden_combs(station.request_io, station.request_hidden_combs, station.request_items)
    end

    if not read_stop_flag(stop, e_stop_flags.custom_name) then
        stop.backer_name = compute_stop_name(station.provide_items, station.request_items)
    end

    storage.stations[station_id] = station
end

---@param unit_number uint
local function try_close_entity_guis(unit_number)
    for player_id, player_gui in pairs(storage.player_guis) do
        if player_gui.unit_number then
            ---@cast player_gui PlayerStationGui
            if player_gui.unit_number == unit_number or player_gui.parts and player_gui.parts.ids[unit_number] then
                gui.station_closed(player_id, player_gui.elements["sspp-station"])
            end
        end
    end
end

---@param items {[ItemKey]: ProvideItem|RequestItem}?
---@param deliveries {[ItemKey]: HaulerId[]}?
local function disable_items_and_haulers(items, deliveries)
    if items then
        ---@cast deliveries {[ItemKey]: HaulerId[]}
        for item_key, _ in pairs(items) do
            storage.disabled_items[item_key] = true
            set_haulers_to_manual(deliveries[item_key], { "sspp-alert.station-broken" })
        end
    end
end

---@param stop LuaEntity
local function try_destroy_station(stop)
    if stop.name == "entity-ghost" then return end

    local station_id = stop.unit_number ---@type StationId
    local station = storage.stations[station_id]
    if station then
        list_remove_value_if_exists(storage.poll_stations, station_id)

        disable_items_and_haulers(station.provide_items, station.provide_deliveries)
        disable_items_and_haulers(station.request_items, station.request_deliveries)

        destroy_hidden_combs(station.provide_hidden_combs)
        destroy_hidden_combs(station.request_hidden_combs)

        storage.stations[station_id] = nil
    end

    if not read_stop_flag(stop, e_stop_flags.custom_name) then
        stop.backer_name = "[virtual-signal=signal-ghost]"
    end
end

--------------------------------------------------------------------------------

---@param stop LuaEntity
---@param ghost_unit_number uint?
function main.stop_built(stop, ghost_unit_number)
    if ghost_unit_number then
        main.stop_broken(ghost_unit_number, nil)
    end

    if not read_stop_flag(stop, e_stop_flags.custom_name) then
        stop.backer_name = "[virtual-signal=signal-ghost]"
    end
    stop.trains_limit = nil

    local stop_cb = stop.get_or_create_control_behavior() --[[@as LuaTrainStopControlBehavior]]
    stop_cb.read_from_train = true

    storage.entities[stop.unit_number] = stop

    local comb_ids, combs = find_nearby_combs(stop)
    storage.stop_comb_ids[stop.unit_number] = comb_ids

    for _, comb in pairs(combs) do
        local stop_ids, stops = find_nearby_stops(comb)
        storage.comb_stop_ids[comb.unit_number] = stop_ids

        for _, other_stop in pairs(stops) do
            try_close_entity_guis(other_stop.unit_number)
            try_destroy_station(other_stop)
        end
    end

    try_create_station(stop, combs)
end

---@param comb LuaEntity
---@param ghost_unit_number uint?
function main.comb_built(comb, ghost_unit_number)
    if ghost_unit_number then
        main.comb_broken(ghost_unit_number, nil)
    end

    local name = comb.name
    if comb.name == "entity-ghost" then name = comb.ghost_name end

    if name == "sspp-general-io" then
        comb.combinator_description = "{}" -- TODO
    elseif name == "sspp-provide-io" then
        comb.combinator_description = provide_items_to_combinator_description(combinator_description_to_provide_items(comb))
    elseif name == "sspp-request-io" then
        comb.combinator_description = request_items_to_combinator_description(combinator_description_to_request_items(comb))
    end

    storage.entities[comb.unit_number] = comb

    local stop_ids, stops = find_nearby_stops(comb)
    storage.comb_stop_ids[comb.unit_number] = stop_ids

    for _, stop in pairs(stops) do
        try_close_entity_guis(stop.unit_number)
        try_destroy_station(stop)

        local comb_ids, combs = find_nearby_combs(stop)
        storage.stop_comb_ids[stop.unit_number] = comb_ids

        try_create_station(stop, combs)
    end
end

--------------------------------------------------------------------------------

---@param stop_id uint
---@param stop LuaEntity?
function main.stop_broken(stop_id, stop)
    local comb_ids = storage.stop_comb_ids[stop_id]

    if stop then
        try_destroy_station(stop)
    end

    storage.entities[stop_id] = nil

    for _, comb_id in pairs(comb_ids) do
        local stop_ids = storage.comb_stop_ids[comb_id]
        list_remove_value(stop_ids, stop_id)

        for _, other_stop_id in pairs(stop_ids) do
            local other_comb_ids = storage.stop_comb_ids[other_stop_id]
            local other_combs = {}
            for _, other_comb_id in pairs(other_comb_ids) do
                other_combs[#other_combs+1] = storage.entities[other_comb_id] -- might be nil
            end
            try_create_station(storage.entities[other_stop_id], other_combs)
        end
    end

    storage.stop_comb_ids[stop_id] = nil
end

---@param comb_id uint
---@param comb LuaEntity?
function main.comb_broken(comb_id, comb)
    local stop_ids = storage.comb_stop_ids[comb_id]

    if comb then
        for _, stop_id in pairs(stop_ids) do
            try_destroy_station(storage.entities[stop_id])
        end
    end

    storage.entities[comb_id] = nil

    for _, stop_id in pairs(stop_ids) do
        local comb_ids = storage.stop_comb_ids[stop_id]
        list_remove_value(comb_ids, comb_id)

        local other_combs = {}
        for _, other_comb_id in pairs(comb_ids) do
            other_combs[#other_combs+1] = storage.entities[other_comb_id] -- might be nil
        end
        try_create_station(storage.entities[stop_id], other_combs)
    end

    storage.comb_stop_ids[comb_id] = nil
end
