-- SSPP by jagoly

local flib_gui = require("__flib__.gui")
local events = defines.events

--------------------------------------------------------------------------------

---@param player_gui PlayerHaulerGui
function gui.hauler_status_changed(player_gui)
    local elements = player_gui.elements
    local train = player_gui.train
    local hauler = storage.haulers[train.id]

    elements.status_label.caption = hauler.status
    if hauler.status_item then
        local name, quality = split_item_key(hauler.status_item)
        if quality then
            elements.item_button.elem_value = { name = name, quality = quality, type = "item" }
        else
            elements.item_button.elem_value = { name = name, type = "fluid" }
        end
    else
        elements.item_button.elem_value = nil
    end
    elements.stop_button.enabled = hauler.status_stop ~= nil
end

--------------------------------------------------------------------------------

---@param event EventData.on_gui_click
local handle_open_network = { [events.on_gui_click] = function(event)
    local player_id = event.player_index
    local network_name = storage.player_guis[player_id].network

    gui.network_open(player_id, network_name)
end }

---@param event EventData.on_gui_click
local handle_stop_clicked = { [events.on_gui_click] = function(event)
    local player_id = event.player_index
    local player_gui = storage.player_guis[player_id] --[[@as PlayerHaulerGui]]

    local hauler = storage.haulers[player_gui.train.id]
    if hauler and hauler.status_stop and hauler.status_stop.valid then
        game.get_player(player_id).centered_on = hauler.status_stop
    end
end }

---@param event EventData.on_gui_text_changed
local handle_class_changed = { [events.on_gui_text_changed] = function(event)
    local player_gui = storage.player_guis[event.player_index] --[[@as PlayerHaulerGui]]
    local train = player_gui.train

    -- disabling textboxes doesn't disable the icon selector, so hope that the user doesn't do that
    -- assert(train.manual_mode, "class name changed when not manual")
    -- update: a user did this, guess I should handle it properly until the api bug gets fixed
    if not train.manual_mode then
        local hauler = storage.haulers[train.id]
        event.element.text = hauler and hauler.class or ""
        return
    end

    local class_name = event.element.text
    -- TODO: validate class name

    local hauler = storage.haulers[train.id]
    if hauler then
        if class_name ~= "" then
            hauler.class = class_name
        else
            storage.haulers[train.id] = nil
        end
    elseif class_name ~= "" then
        storage.haulers[train.id] = {
            train = train,
            network = player_gui.network,
            class = class_name,
        }
    end
end }

---@param carriage LuaEntity
local function map_carriage_name(carriage)
    -- TODO: Adjust names of carriages that should be treated as identical. For example, the
    -- locomotives from Multiple Unit Train Control should map to the same strings as the
    -- entities that they are derived from.
    return carriage.name
end

---@param event EventData.on_gui_click
local handle_class_auto_assign = { [events.on_gui_click] = function(event)
    local player_gui = storage.player_guis[event.player_index] --[[@as PlayerHaulerGui]]
    local new_train = player_gui.train
    local new_hauler_id = new_train.id

    local new_carriage_names, new_length = {}, 0 ---@type string[], integer
    for _, carriage in pairs(new_train.carriages) do
        new_length = new_length + 1
        new_carriage_names[new_length] = map_carriage_name(carriage)
    end

    local matching_class ---@type ClassName?
    local classes_with_haulers = {} ---@type {[ClassName]: true?}

    -- first, try to find a class that already has an identical train
    for hauler_id, hauler in pairs(storage.haulers) do
        local class_name = hauler.class

        if class_name ~= matching_class and hauler_id ~= new_hauler_id then
            local carriages = hauler.train.carriages
            local length = #carriages

            if length == new_length then
                for i = 1, length do
                    if map_carriage_name(carriages[i]) ~= new_carriage_names[i] then goto continue end
                end
                if matching_class then
                    -- TODO: show this in the widget rather than sending an alert
                    send_alert_for_train(new_train, { "sspp-alert.auto-assign-multiple-classes" })
                    return
                end
                matching_class = class_name
            end

            classes_with_haulers[class_name] = true
        end

        ::continue::
    end

    -- second, try to find a newly added class with no trains
    if not matching_class then
        for class_name, _ in pairs(storage.networks[player_gui.network].classes) do
            if not classes_with_haulers[class_name] then
                if matching_class then
                    -- TODO: show this in the widget rather than sending an alert
                    send_alert_for_train(new_train, { "sspp-alert.auto-assign-multiple-classes" })
                    return
                end
                matching_class = class_name
            end
        end
    end

    if not matching_class then
        send_alert_for_train(new_train, { "sspp-alert.auto-assign-no-class" })
        return
    end

    storage.haulers[new_hauler_id] = {
        train = new_train,
        network = player_gui.network,
        class = matching_class,
    }
    player_gui.elements.class_textbox.text = matching_class

    new_train.manual_mode = false
end }

--------------------------------------------------------------------------------

---@param player_id PlayerId
---@param hauler_id HaulerId
function gui.hauler_opened(player_id, hauler_id)
    local player = game.get_player(player_id) --[[@as LuaPlayer]]
    local train = game.train_manager.get_train_by_id(hauler_id) --[[@as LuaTrain]]

    local network_name = train.front_stock.surface.name
    local manual_mode = train.manual_mode

    -- mods assigning player.opened to another locomotive won't generate a close event
    if player.gui.screen["sspp-hauler"] then
        gui.hauler_closed(player_id)
    end

    local elements, window = flib_gui.add(player.gui.screen, {
        { type = "frame", name = "sspp-hauler", style = "sspp_hauler_frame", direction = "vertical", children = {
            { type = "flow", style = "flib_indicator_flow", children = {
                { type = "label", style = "frame_title", caption = { "sspp-gui.sspp" } },
                { type = "empty-widget", style = "flib_horizontal_pusher" },
                { type = "button", style = "sspp_frame_tool_button", caption = { "sspp-gui.network" }, mouse_button_filter = { "left" }, handler = handle_open_network },
            } },
            { type = "flow", style = "flib_indicator_flow", children = {
                { type = "label", name = "status_label", style = "label" },
                { type = "empty-widget", style = "flib_horizontal_pusher" },
                { type = "choose-elem-button", name = "item_button", style = "sspp_compact_slot_button", elem_type = "signal", enabled = false },
                { type = "sprite-button", name = "stop_button", style = "sspp_compact_slot_button", sprite = "item/train-stop", mouse_button_filter = { "left" }, handler = handle_stop_clicked },
            } },
            { type = "flow", style = "flib_indicator_flow", children = {
                { type = "label", style = "bold_label", caption = { "sspp-gui.class" } },
                { type = "empty-widget", style = "flib_horizontal_pusher" },
                { type = "textfield", name = "class_textbox", style = "sspp_name_textbox", icon_selector = true, enabled = manual_mode, handler = handle_class_changed },
                { type = "sprite-button", name = "class_auto_assign_button", style = "sspp_compact_slot_button", sprite = "sspp-refresh-icon", tooltip = { "sspp-gui.hauler-auto-assign-tooltip" }, mouse_button_filter = { "left" }, enabled = manual_mode, handler = handle_class_auto_assign },
            } },
        } },
    })

    local resolution, scale = player.display_resolution, player.display_scale
    window.location = { x = resolution.width - (224 + 12) * scale, y = resolution.height - (108 + 12) * scale }

    local player_gui = { network = network_name, train = train, elements = elements }
    storage.player_guis[player_id] = player_gui

    local hauler = storage.haulers[hauler_id]
    if hauler then
        elements.class_textbox.text = hauler.class
        gui.hauler_status_changed(player_gui)
    else
        elements.status_label.caption = { "sspp-gui.not-configured" }
        elements.stop_button.enabled = false
    end
end

---@param player_id PlayerId
function gui.hauler_closed(player_id)
    local player = game.get_player(player_id) --[[@as LuaPlayer]]

    player.gui.screen["sspp-hauler"].destroy()

    storage.player_guis[player_id] = nil
end

--------------------------------------------------------------------------------

function gui.hauler_add_flib_handlers()
    flib_gui.add_handlers({
        ["hauler_open_network"] = handle_open_network[events.on_gui_click],
        ["hauler_stop_clicked"] = handle_stop_clicked[events.on_gui_click],
        ["hauler_class_changed"] = handle_class_changed[events.on_gui_text_changed],
        ["hauler_class_auto_assign"] = handle_class_auto_assign[events.on_gui_click],
    })
end
