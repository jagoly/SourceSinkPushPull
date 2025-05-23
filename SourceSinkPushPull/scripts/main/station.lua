-- SSPP by jagoly

local config = require("__SourceSinkPushPull__.scripts.config")
local lib = require("__SourceSinkPushPull__.scripts.lib")
local gui = require("__SourceSinkPushPull__.scripts.gui")

---@class sspp.main.station
local main_station = {}

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
    if stop.name == "entity-ghost" or not stop.connected_rail then return end

    local station_id = stop.unit_number --[[@as StationId]]
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

    local unit_numbers = { [stop.unit_number] = true, [general_io.unit_number] = true }

    local station_stop = lib.read_station_stop_settings(stop)
    local station_general = lib.read_station_general_settings(general_io)

    local station_provide = nil
    if provide_io then
        unit_numbers[provide_io.unit_number] = true

        local stop_connector = stop.get_wire_connector(defines.wire_connector_id.circuit_red, true)
        local io_connector = provide_io.get_wire_connector(defines.wire_connector_id.combinator_input_red, true)
        stop_connector.connect_to(io_connector, true)

        station_provide = lib.read_station_provide_settings(provide_io) ---@cast station_provide StationProvide
        station_provide.deliveries, station_provide.hidden_combs, station_provide.counts, station_provide.modes = {}, {}, {}, {}

        lib.ensure_hidden_combs(provide_io, station_provide.hidden_combs, station_provide.items)
    end

    local station_request = nil
    if request_io then
        unit_numbers[request_io.unit_number] = true

        local stop_connector = stop.get_wire_connector(defines.wire_connector_id.circuit_green, true)
        local io_connector = request_io.get_wire_connector(defines.wire_connector_id.combinator_input_green, true)
        stop_connector.connect_to(io_connector, true)

        station_request = lib.read_station_request_settings(request_io) ---@cast station_request StationRequest
        station_request.deliveries, station_request.hidden_combs, station_request.counts, station_request.modes = {}, {}, {}, {}

        lib.ensure_hidden_combs(request_io, station_request.hidden_combs, station_request.items)
    end

    if not station_stop.custom_name then
        stop.backer_name = lib.generate_stop_name(station_provide and station_provide.items, station_request and station_request.items)
    end

    storage.stations[station_id] = {
        stop = station_stop, general = station_general, provide = station_provide, request = station_request,
        unit_numbers = unit_numbers, total_deliveries = 0,
    }
end

---@param stop LuaEntity
local function try_destroy_station(stop)
    if stop.name == "entity-ghost" then return end

    local station_id = stop.unit_number --[[@as StationId]]
    local station = storage.stations[station_id]
    if not station then return end

    lib.list_remove_if_exists(storage.poll_stations, station_id)

    if station.provide then
        for item_key, _ in pairs(station.provide.items) do
            storage.disabled_items[station.general.network .. ":" .. item_key] = true
            lib.set_haulers_to_manual(station.provide.deliveries[item_key], { "sspp-alert.station-broken" })
        end
        lib.destroy_hidden_combs(station.provide.hidden_combs)
    end

    if station.request then
        for item_key, _ in pairs(station.request.items) do
            storage.disabled_items[station.general.network .. ":" .. item_key] = true
            lib.set_haulers_to_manual(station.request.deliveries[item_key], { "sspp-alert.station-broken" })
        end
        lib.destroy_hidden_combs(station.request.hidden_combs)
    end

    if not station.stop.custom_name then stop.backer_name = "[virtual-signal=signal-ghost]" end

    storage.stations[station_id] = nil
end

--------------------------------------------------------------------------------

---@param stop LuaEntity
function main_station.on_stop_built(stop)
    local station_stop = lib.read_station_stop_settings(stop)
    lib.write_station_stop_settings(station_stop)
    if stop.trains_limit > 10 or stop.trains_limit < 1 then stop.trains_limit = config.default_train_limit end
    if not station_stop.custom_name then stop.backer_name = "[virtual-signal=signal-ghost]" end

    local stop_cb = stop.get_or_create_control_behavior() --[[@as LuaTrainStopControlBehavior]]
    stop_cb.read_from_train = true

    storage.entities[stop.unit_number] = stop

    local comb_ids, combs = find_nearby_combs(stop)
    storage.stop_comb_ids[stop.unit_number] = comb_ids

    for _, comb in pairs(combs) do
        local stop_ids, stops = find_nearby_stops(comb)
        storage.comb_stop_ids[comb.unit_number] = stop_ids

        for _, other_stop in pairs(stops) do
            gui.on_part_broken(other_stop.unit_number)
            try_destroy_station(other_stop)
        end
    end

    try_create_station(stop, combs)
end

---@param comb LuaEntity
function main_station.on_comb_built(comb)
    local name = comb.name
    if name == "entity-ghost" then name = comb.ghost_name end

    if name == "sspp-general-io" then
        lib.write_station_general_settings(lib.read_station_general_settings(comb))
    elseif name == "sspp-provide-io" then
        lib.write_station_provide_settings(lib.read_station_provide_settings(comb))
        lib.clear_control_behavior(comb)
    elseif name == "sspp-request-io" then
        lib.write_station_request_settings(lib.read_station_request_settings(comb))
        lib.clear_control_behavior(comb)
    end

    storage.entities[comb.unit_number] = comb

    local stop_ids, stops = find_nearby_stops(comb)
    storage.comb_stop_ids[comb.unit_number] = stop_ids

    for _, stop in pairs(stops) do
        gui.on_part_broken(stop.unit_number)
        try_destroy_station(stop)

        local comb_ids, combs = find_nearby_combs(stop)
        storage.stop_comb_ids[stop.unit_number] = comb_ids

        try_create_station(stop, combs)
    end
end

---@param rail LuaEntity
function main_station.on_rail_built(rail)
    for _, direction in pairs(defines.rail_direction) do
        do
            local stop = rail.get_rail_segment_stop(direction)

            if not stop or stop.name ~= "sspp-stop" then
                goto continue -- not connected to the right kind of stop
            end
            if stop.connected_rail ~= rail then
                goto continue -- rail is not the last in the segment
            end
            if storage.stations[stop.unit_number] then
                goto continue -- another build event already created a station
            end
            if not storage.entities[stop.unit_number] then
                goto continue -- build event for the stop hasn't happened yet
            end

            local x, y, combs = stop.position.x, stop.position.y, {}
            for _, entity in pairs(stop.surface.find_entities({ { x - 2.6, y - 2.6 }, { x + 2.6, y + 2.6 } })) do
                local name = entity.name
                if name == "entity-ghost" then
                    name = entity.ghost_name
                    if name == "sspp-general-io" or name == "sspp-provide-io" or name == "sspp-request-io" then
                        goto continue -- this comb is a ghost
                    end
                elseif name == "sspp-general-io" or name == "sspp-provide-io" or name == "sspp-request-io" then
                    if not storage.entities[entity.unit_number] then
                        goto continue -- build event for this comb hasn't happened yet
                    end
                    combs[#combs+1] = entity
                end
            end

            try_create_station(stop, combs)
        end
        ::continue::
    end
end

--------------------------------------------------------------------------------

---@param stop_id uint
---@param stop LuaEntity?
function main_station.on_stop_broken(stop_id, stop)
    local comb_ids = storage.stop_comb_ids[stop_id]

    gui.on_part_broken(stop_id)
    if stop then
        try_destroy_station(stop)
    end

    storage.entities[stop_id] = nil

    for _, comb_id in pairs(comb_ids) do
        local stop_ids = storage.comb_stop_ids[comb_id]
        lib.list_remove(stop_ids, stop_id)

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
function main_station.on_comb_broken(comb_id, comb)
    local stop_ids = storage.comb_stop_ids[comb_id]

    gui.on_part_broken(comb_id)
    if comb then
        for _, stop_id in pairs(stop_ids) do
            try_destroy_station(storage.entities[stop_id])
        end
    end

    storage.entities[comb_id] = nil

    for _, stop_id in pairs(stop_ids) do
        local comb_ids = storage.stop_comb_ids[stop_id]
        lib.list_remove(comb_ids, comb_id)

        local other_combs = {}
        for _, other_comb_id in pairs(comb_ids) do
            other_combs[#other_combs+1] = storage.entities[other_comb_id] -- might be nil
        end
        try_create_station(storage.entities[stop_id], other_combs)
    end

    storage.comb_stop_ids[comb_id] = nil
end

---@param rail LuaEntity
function main_station.on_rail_broken(rail)
    for _, direction in pairs(defines.rail_direction) do
        do
            local stop = rail.get_rail_segment_stop(direction)

            if not stop or stop.name ~= "sspp-stop" then
                goto continue -- not connected to the right kind of stop
            end
            if stop.connected_rail ~= rail then
                goto continue -- rail is not the last in the segment
            end

            try_destroy_station(stop)
        end
        ::continue::
    end
end

--------------------------------------------------------------------------------

function main_station.destory_invalid_entities()
    local stop_comb_ids, comb_stop_ids = storage.stop_comb_ids, storage.comb_stop_ids
    for unit_number, entity in pairs(storage.entities) do
        if not entity.valid then
            if stop_comb_ids[unit_number] then
                main_station.on_stop_broken(unit_number)
            elseif comb_stop_ids[unit_number] then
                main_station.on_comb_broken(unit_number)
            end
        end
    end
end

--------------------------------------------------------------------------------

return main_station
