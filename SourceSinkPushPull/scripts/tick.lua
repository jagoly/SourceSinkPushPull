-- SSPP by jagoly

--------------------------------------------------------------------------------

---@param list NetworkItemKey[]
---@param length integer
---@param network_name NetworkName
---@param item_key ItemKey
---@param copies integer
---@return integer new_length
local function extend_network_item_key_list(list, length, network_name, item_key, copies)
    if copies > 0 then
        local network_item_key = network_name .. ":" .. item_key
        for i = length + 1, length + copies do
            list[i] = network_item_key
        end
        length = length + copies
    end
    return length
end

---@param dict {[ItemKey]: StationId[]}
---@param key ItemKey
---@return StationId
local function pop_random_station_from_partition_or_destroy(dict, key)
    local list = dict[key]
    local length = #list

    if length > 1 then
        local stations = storage.stations

        local best_total = math.huge
        for _, station_id in pairs(list) do
            local total = stations[station_id].total_deliveries
            if total < best_total then best_total = total end
        end

        local best_index_list = {}
        for index, station_id in pairs(list) do
            local total = stations[station_id].total_deliveries
            if total == best_total then best_index_list[#best_index_list+1] = index end
        end

        local index = best_index_list[math.random(#best_index_list)]

        local result = list[index]
        list[index] = list[length]
        list[length] = nil

        return result
    end

    if length > 0 then
        local result = list[1]
        dict[key] = nil

        return result
    end

    error("empty list")
end

--------------------------------------------------------------------------------

local function prepare_for_tick_poll()
    for _, network in pairs(storage.networks) do
        network.push_tickets = {}
        network.provide_tickets = {}
        network.pull_tickets = {}
        network.request_tickets = {}
        network.provide_done_tickets = {}
        network.request_done_tickets = {}
    end

    storage.disabled_items = {}

    local list, length = {}, 0 ---@type StationId[]
    storage.poll_stations = list

    for station_id, station in pairs(storage.stations) do
        -- TODO: add on/off switch to station, check it here
        local provide_items = station.provide_items
        if not (provide_items and next(provide_items)) then
            local request_items = station.request_items
            if not (request_items and next(request_items)) then
                goto continue
            end
        end
        length = length + 1
        list[length] = station_id
        ::continue::
    end

    storage.tick_state = "POLL"
end

local function tick_poll()
    local station_id = list_pop_random_if_any(storage.poll_stations)
    if not station_id then return true end

    local station = storage.stations[station_id]
    local network = storage.networks[station.network]

    local hauler_provide_item_key, hauler_request_item_key ---@type ItemKey?, ItemKey?

    local hauler_id = station.hauler
    if hauler_id then
        local hauler = storage.haulers[hauler_id]
        if hauler.to_provide then
            if hauler.to_provide.phase == "DONE" then
                hauler_provide_item_key = hauler.to_provide.item
                list_append_or_create(network.provide_done_tickets, hauler_provide_item_key, station_id)
            end
        else
            if hauler.to_request.phase == "DONE" then
                hauler_request_item_key = hauler.to_request.item
                list_append_or_create(network.request_done_tickets, hauler_request_item_key, station_id)
            end
        end
    end

    local storage_counts = {} ---@type {[ItemKey]: integer}

    local storage_signals = station.general_io.get_signals(defines.wire_connector_id.combinator_input_red, defines.wire_connector_id.combinator_input_green)
    if storage_signals then
        for _, signal in pairs(storage_signals) do
            local id = signal.signal
            local type = id.type or "item"
            if type == "item" then
                storage_counts[id.name .. ":" .. (id.quality or "normal")] = signal.count
            elseif type == "fluid" then
                storage_counts[id.name] = signal.count
            end
        end
    end

    if station.provide_items then
        local provide_counts = {} ---@type {[ItemKey]: integer}
        station.provide_counts = provide_counts

        for item_key, provide_item in pairs(station.provide_items) do
            local network_item = network.items[item_key]
            if network_item then
                -- for provide items, count is the number of items in storage
                local count = storage_counts[item_key] or 0
                provide_counts[item_key] = count

                if hauler_provide_item_key == item_key then
                    local minimum_count = station.provide_minimum_active_count ---@type integer
                    if minimum_count > count then
                        count = minimum_count
                    elseif minimum_count < count then
                        station.provide_minimum_active_count = count
                    end
                    hauler_provide_item_key = nil
                end

                local deliveries = len_or_zero(station.provide_deliveries[item_key])
                local want_deliveries = math.floor(count / network_item.delivery_size) - deliveries
                if want_deliveries > 0 then
                    if provide_item.push then
                        local push_count = count - compute_buffer(network_item, provide_item)
                        local push_want_deliveries = math.floor(push_count / network_item.delivery_size) - deliveries
                        if push_want_deliveries > 0 then
                            list_extend_or_create(network.push_tickets, item_key, station_id, push_want_deliveries)
                            want_deliveries = want_deliveries - push_want_deliveries
                        end
                    end
                    if want_deliveries > 0 then
                        list_extend_or_create(network.provide_tickets, item_key, station_id, want_deliveries)
                    end
                end
            end
        end
    end

    if station.request_items then
        local request_counts = {} ---@type {[ItemKey]: integer}
        station.request_counts = request_counts

        for item_key, request_item in pairs(station.request_items) do
            local network_item = network.items[item_key]
            if network_item then
                -- for request items, count is the number of items missing from storage
                local count = compute_storage_needed(network_item, request_item) - (storage_counts[item_key] or 0)
                request_counts[item_key] = count

                if hauler_request_item_key == item_key then
                    local minimum_count = station.request_minimum_active_count ---@type integer
                    if minimum_count > count then
                        count = minimum_count
                    elseif minimum_count < count then
                        station.request_minimum_active_count = count
                    end
                    hauler_request_item_key = nil
                end

                local deliveries = len_or_zero(station.request_deliveries[item_key])
                local want_deliveries = math.floor(count / network_item.delivery_size) - deliveries
                if want_deliveries > 0 then
                    if request_item.pull then
                        local pull_count = count - compute_buffer(network_item, request_item)
                        local pull_want_deliveries = math.floor(pull_count / network_item.delivery_size) - deliveries
                        if pull_want_deliveries > 0 then
                            list_extend_or_create(network.pull_tickets, item_key, station_id, pull_want_deliveries)
                            want_deliveries = want_deliveries - pull_want_deliveries
                        end
                    end
                    if want_deliveries > 0 then
                        list_extend_or_create(network.request_tickets, item_key, station_id, want_deliveries)
                    end
                end
            end
        end
    end

    if hauler_provide_item_key or hauler_request_item_key then
        error("station assigned to incorrect hauler")
    end

    return false
end

--------------------------------------------------------------------------------

local function prepare_for_tick_liquidate()
    local list, length = {}, 0 ---@type NetworkItemKey[]
    storage.liquidate_items = list

    for network_name, network in pairs(storage.networks) do
        local pull_tickets = network.pull_tickets
        local request_tickets = network.request_tickets
        local items = network.items
        local classes = network.classes

        local tickets_remaining = {} ---@type {[ItemKey]: integer}

        for item_key, hauler_ids in pairs(network.at_depot_liquidate_haulers) do
            local tickets = len_or_zero(pull_tickets[item_key]) + len_or_zero(request_tickets[item_key])
            local haulers_to_send = math.min(#hauler_ids, tickets)

            tickets_remaining[item_key] = tickets - haulers_to_send
            length = extend_network_item_key_list(list, length, network_name, item_key, haulers_to_send)
        end

        for item_key, hauler_ids in pairs(network.to_depot_liquidate_haulers) do
            if classes[items[item_key].class].bypass_depot then
                local tickets = tickets_remaining[item_key] or (len_or_zero(pull_tickets[item_key]) + len_or_zero(request_tickets[item_key]))
                local haulers_to_send = math.min(#hauler_ids, tickets)

                length = extend_network_item_key_list(list, length, network_name, item_key, haulers_to_send)
            end
        end
    end

    storage.tick_state = "LIQUIDATE"
end

local function tick_liquidate()
    local network_name, item_key ---@type NetworkName, ItemKey

    repeat
        local network_item_key = list_pop_random_if_any(storage.liquidate_items)
        if not network_item_key then return true end

        if storage.disabled_items[network_item_key] then goto continue end

        network_name, item_key = string.match(network_item_key, "(.-):(.+)")

        break; ::continue::
    until false

    local network = storage.networks[network_name]

    local hauler_id ---@type HaulerId
    if network.at_depot_liquidate_haulers[item_key] then
        hauler_id = list_pop_random_or_destroy(network.at_depot_liquidate_haulers, item_key)
    else
        hauler_id = list_pop_random_or_destroy(network.to_depot_liquidate_haulers, item_key)
    end
    local hauler = storage.haulers[hauler_id]
    hauler.to_depot = nil
    hauler.at_depot = nil

    local request_station_id ---@type StationId
    if network.pull_tickets[item_key] then
        request_station_id = pop_random_station_from_partition_or_destroy(network.pull_tickets, item_key)
    else
        request_station_id = pop_random_station_from_partition_or_destroy(network.request_tickets, item_key)
    end
    local request_station = storage.stations[request_station_id]

    list_append_or_create(network.request_haulers, item_key, hauler_id)
    list_append_or_create(request_station.request_deliveries, item_key, hauler_id)
    hauler.to_request = { item = item_key, station = request_station_id, phase = "TRAVEL" }
    request_station.total_deliveries = request_station.total_deliveries + 1

    set_hauler_status(hauler, { "sspp-alert.dropping-off-cargo" }, item_key, request_station.stop)
    send_hauler_to_station(hauler, request_station.stop)

    return false
end

--------------------------------------------------------------------------------

local function prepare_for_tick_dispatch()
    local list, length = {}, 0 ---@type NetworkItemKey[]
    storage.dispatch_items = list

    for network_name, network in pairs(storage.networks) do
        local provide_haulers = network.provide_haulers

        local push_tickets = network.push_tickets
        local provide_tickets = network.provide_tickets
        local pull_tickets = network.pull_tickets
        local request_tickets = network.request_tickets

        for item_key, _ in pairs(network.items) do
            local haulers_to_send = 0
            local push_count = len_or_zero(push_tickets[item_key])
            local pull_count = len_or_zero(pull_tickets[item_key])

            if push_count > 0 then
                local request_total = pull_count + len_or_zero(request_tickets[item_key])
                haulers_to_send = math.min(push_count, request_total)
            end

            if pull_count > 0 then
                local real_pull_count = pull_count - len_or_zero(provide_haulers[item_key])
                local provide_total = push_count + len_or_zero(provide_tickets[item_key])
                haulers_to_send = math.max(haulers_to_send, math.min(real_pull_count, provide_total))
            end

            length = extend_network_item_key_list(list, length, network_name, item_key, haulers_to_send)
        end
    end

    storage.tick_state = "DISPATCH"
end

---@param network Network
---@param item_key NetworkItemKey
---@return HaulerId|nil
local function find_hauler_for_item(network, item_key)
    local search_hauler_class = function(class_name)
        if network.at_depot_haulers[class_name] then
            return list_pop_random_or_destroy(network.at_depot_haulers, class_name)
        end

        if network.to_depot_haulers[class_name] and network.classes[class_name].bypass_depot then
            return list_pop_random_or_destroy(network.to_depot_haulers, class_name)
        end

        return nil
    end

    local search_all_haulers = function(item_slots, fluid_capacity)
        for class_name, class in pairs(network.classes) do
            if class.fluid_capacity >= fluid_capacity and class.item_slot_capacity >= item_slots then
                local hauler_id = search_hauler_class(class_name)
                if hauler_id ~= nil then return hauler_id end
            end
        end
    end

    local item = network.items[item_key]
    local class_name = item.class
    if class_name ~= "" then
        -- Use item class if defined
        return search_hauler_class(class_name)
    else
        local prototype = prototypes.item[item.name]
        if prototype then
            -- Item prototype
            return search_all_haulers(item.delivery_size / prototype.stack_size, 0)
        else
            -- Fluid prototype
            return search_all_haulers(0, item.delivery_size)
        end
    end
end

local function tick_dispatch()
    local network_name, item_key ---@type NetworkName, ItemKey
    local network ---@type Network
    local hauler_id ---@type HaulerId

    repeat
        local network_item_key = list_pop_random_if_any(storage.dispatch_items)
        local found_hauler_id
        if not network_item_key then return true end

        if storage.disabled_items[network_item_key] then goto continue end

        network_name, item_key = string.match(network_item_key, "(.-):(.+)")
        network = storage.networks[network_name]

        found_hauler_id = find_hauler_for_item(network, item_key)
        if found_hauler_id ~= nil then
            hauler_id = found_hauler_id
            break
        end

        ::continue::
    until false

    local hauler = storage.haulers[hauler_id]
    hauler.to_depot = nil
    hauler.at_depot = nil

    local provide_station_id ---@type StationId
    if network.push_tickets[item_key] then
        provide_station_id = pop_random_station_from_partition_or_destroy(network.push_tickets, item_key)
    else
        provide_station_id = pop_random_station_from_partition_or_destroy(network.provide_tickets, item_key)
    end
    local provide_station = storage.stations[provide_station_id]

    list_append_or_create(network.provide_haulers, item_key, hauler_id)
    list_append_or_create(provide_station.provide_deliveries, item_key, hauler_id)
    hauler.to_provide = { item = item_key, station = provide_station_id, phase = "TRAVEL" }
    provide_station.total_deliveries = provide_station.total_deliveries + 1

    set_hauler_status(hauler, { "sspp-alert.picking-up-cargo" }, item_key, provide_station.stop)
    send_hauler_to_station(hauler, provide_station.stop)

    return false
end

--------------------------------------------------------------------------------

local function prepare_for_tick_provide_done()
    local list, length = {}, 0 ---@type NetworkItemKey[]
    storage.provide_done_items = list

    for network_name, network in pairs(storage.networks) do
        local pull_tickets = network.pull_tickets
        local request_tickets = network.request_tickets

        for item_key, station_ids in pairs(network.provide_done_tickets) do
            local pull_count = len_or_zero(pull_tickets[item_key])
            local request_count = len_or_zero(request_tickets[item_key])
            local haulers_to_send = math.min(#station_ids, pull_count + request_count)

            length = extend_network_item_key_list(list, length, network_name, item_key, haulers_to_send)
        end
    end

    storage.tick_state = "PROVIDE_DONE"
end

local function tick_provide_done()
    local network_name, item_key ---@type NetworkName, ItemKey

    repeat
        local network_item_key = list_pop_random_if_any(storage.provide_done_items)
        if not network_item_key then return true end

        if storage.disabled_items[network_item_key] then goto continue end

        network_name, item_key = string.match(network_item_key, "(.-):(.+)")

        break; ::continue::
    until false

    local network = storage.networks[network_name]

    local provide_station_id = list_pop_random_or_destroy(network.provide_done_tickets, item_key)
    local provide_station = storage.stations[provide_station_id]

    local hauler_id = assert(provide_station.hauler)
    local hauler = storage.haulers[hauler_id]

    list_remove_value_or_destroy(network.provide_haulers, item_key, hauler_id)
    list_remove_value_or_destroy(provide_station.provide_deliveries, item_key, hauler_id)
    hauler.to_provide = nil
    provide_station.provide_minimum_active_count = nil
    provide_station.hauler = nil
    provide_station.total_deliveries = provide_station.total_deliveries - 1

    local request_station_id ---@type StationId
    if network.pull_tickets[item_key] then
        request_station_id = pop_random_station_from_partition_or_destroy(network.pull_tickets, item_key)
    else
        request_station_id = pop_random_station_from_partition_or_destroy(network.request_tickets, item_key)
    end
    local request_station = storage.stations[request_station_id]

    list_append_or_create(network.request_haulers, item_key, hauler_id)
    list_append_or_create(request_station.request_deliveries, item_key, hauler_id)
    hauler.to_request = { item = item_key, station = request_station_id, phase = "TRAVEL" }
    request_station.total_deliveries = request_station.total_deliveries + 1

    set_hauler_status(hauler, { "sspp-alert.dropping-off-cargo" }, item_key, request_station.stop)
    send_hauler_to_station(hauler, request_station.stop)

    return false
end

--------------------------------------------------------------------------------

local function prepare_for_tick_request_done()
    local list, length = {}, 0 ---@type NetworkItemKey[]
    storage.request_done_items = list

    for network_name, network in pairs(storage.networks) do
        for item_key, station_ids in pairs(network.request_done_tickets) do
            -- assume there are always enough depots available
            local haulers_to_send = #station_ids
            length = extend_network_item_key_list(list, length, network_name, item_key, haulers_to_send)
        end
    end

    storage.tick_state = "REQUEST_DONE"
end

local function tick_request_done()
    local network_name, item_key ---@type NetworkName, ItemKey

    repeat
        local network_item_key = list_pop_random_if_any(storage.request_done_items)
        if not network_item_key then return true end

        if storage.disabled_items[network_item_key] then goto continue end

        network_name, item_key = string.match(network_item_key, "(.-):(.+)")

        break; ::continue::
    until false

    local network = storage.networks[network_name]

    local request_station_id = list_pop_random_or_destroy(network.request_done_tickets, item_key)
    local request_station = storage.stations[request_station_id]

    local hauler_id = assert(request_station.hauler)
    local hauler = storage.haulers[hauler_id]

    list_remove_value_or_destroy(network.request_haulers, item_key, hauler_id)
    list_remove_value_or_destroy(request_station.request_deliveries, item_key, hauler_id)
    hauler.to_request = nil
    request_station.request_minimum_active_count = nil
    request_station.hauler = nil
    request_station.total_deliveries = request_station.total_deliveries - 1

    local class = network.classes[hauler.class]
    if class then
        if check_if_hauler_needs_fuel(hauler, class) then
            list_append_or_create(network.fuel_haulers, hauler.class, hauler_id)
            hauler.to_fuel = "TRAVEL"
            set_hauler_status(hauler, { "sspp-alert.getting-fuel" })
            send_hauler_to_named_stop(hauler, class.fueler_name)
        else
            list_append_or_create(network.to_depot_haulers, hauler.class, hauler_id)
            hauler.to_depot = ""
            set_hauler_status(hauler, { class.bypass_depot and "sspp-alert.ready-for-dispatch" or "sspp-alert.going-to-depot" })
            send_hauler_to_named_stop(hauler, class.depot_name)
        end
    else
        set_hauler_status(hauler, { "sspp-alert.class-not-in-network" })
        send_alert_for_train(hauler.train, hauler.status)
        hauler.train.manual_mode = true
    end

    return false
end

-------------------------------------------------------------------------------

function on_tick()
    local tick_state = storage.tick_state

    if tick_state == "POLL" then
        for _ = 1, mod_settings.stations_per_tick do
            if tick_poll() then
                gui.on_poll_finished()
                prepare_for_tick_liquidate()
                break
            end
        end
    elseif tick_state == "LIQUIDATE" then
        if tick_liquidate() then
            prepare_for_tick_dispatch()
        end
    elseif tick_state == "DISPATCH" then
        if tick_dispatch() then
            prepare_for_tick_provide_done()
        end
    elseif tick_state == "PROVIDE_DONE" then
        if tick_provide_done() then
            prepare_for_tick_request_done()
        end
    elseif tick_state == "REQUEST_DONE" then
        if tick_request_done() then
            prepare_for_tick_poll()
        end
    elseif tick_state == "INITIAL" then
        prepare_for_tick_poll()
    end
end
