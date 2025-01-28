-- SSPP by jagoly

local flib_gui = require("__flib__.gui")

gui = {}

require("gui.network")
require("gui.station")
require("gui.hauler")

--------------------------------------------------------------------------------

---@param event EventData.on_gui_opened
local function on_gui_opened(event)
    if event.gui_type == defines.gui_type.entity then
        local entity = event.entity ---@type LuaEntity
        local name = entity.name
        if name == "entity-ghost" then name = entity.ghost_name end
        if name == "sspp-stop" or name == "sspp-general-io" or name == "sspp-provide-io" or name == "sspp-request-io" then
            gui.station_open(event.player_index, entity)
        elseif entity.type == "locomotive" then
            gui.hauler_opened(event.player_index, entity.train.id)
        end
    end
end

---@param event EventData.on_gui_closed
local function on_gui_closed(event)
    if event.gui_type == defines.gui_type.custom then
        if event.element.name == "sspp-network" then
            gui.network_closed(event.player_index, event.element)
        elseif event.element.name == "sspp-station" then
            gui.station_closed(event.player_index, event.element)
        end
    elseif event.gui_type == defines.gui_type.entity then
        if event.entity.type == "locomotive" then
            gui.hauler_closed(event.player_index)
        end
    end
end

function gui.on_poll_finished()
    for _, player_gui in pairs(storage.player_guis) do
        if player_gui.unit_number then
            gui.station_poll_finished(player_gui --[[@as PlayerStationGui]])
        elseif player_gui.train then
            -- gui.hauler_poll_finished(player_gui --[[@as PlayerHaulerGui]])
        else
            gui.network_poll_finished(player_gui --[[@as PlayerNetworkGui]])
        end
    end
end

--------------------------------------------------------------------------------

---@param table LuaGuiElement
---@param flow_index integer
---@param button_index integer
function gui.move_row(table, flow_index, button_index)
    local columns = table.column_count
    local i = flow_index - 1
    local j = i + (button_index * 2 - 3) * columns
    if j >= columns and j + columns <= #table.children then
        for c = 1, columns do
            table.swap_children(i + c, j + c)
        end
    end
end

---@param table LuaGuiElement
---@param flow_index integer
function gui.delete_row(table, flow_index)
    local children = table.children
    for i = flow_index - 1 + table.column_count, flow_index, -1 do
        children[i].destroy()
    end
end

---@param table LuaGuiElement
---@param destination_i integer
function gui.insert_newly_added_row(table, destination_i)
    local columns = table.column_count
    for i = #table.children - columns, destination_i + columns, -columns do
        for c = 1, columns do
            table.swap_children(i + c, i + c - columns)
        end
    end
end

---@param elem_value table|string
---@return string name, string? quality, ItemKey item_key
function gui.extract_elem_value_fields(elem_value)
    local name, quality, item_key ---@type string, string?, ItemKey
    if type(elem_value) == "table" then
        name = elem_value.name
        quality = elem_value.quality or "normal"
        item_key = name .. ":" .. quality
    else
        name = elem_value --[[@as string]]
        item_key = name
    end
    return name, quality, item_key
end

---@param table LuaGuiElement
---@param from_row fun(table_children: LuaGuiElement[], i: integer): key: string?, value: any
---@param to_row fun(table_children: LuaGuiElement[], i: integer, key: string?, value: any)
---@param old_dict {[string]: any}?
---@param key_remove fun(key: string)?
---@return {[string]: any}
function gui.refresh_table(table, from_row, to_row, old_dict, key_remove)
    local columns = table.column_count
    local table_children = table.children

    local new_dict = {}

    for i = columns, #table_children - 1, columns do
        local key, value = from_row(table_children, i)

        if key then
            if new_dict[key] then
                key, value = nil, nil
            else
                new_dict[key] = value
            end
        end

        to_row(table_children, i, key, value)
    end

    if old_dict then
        ---@cast key_remove fun(key: string)
        for key, _ in pairs(old_dict) do
            if not new_dict[key] then key_remove(key) end
        end
    end

    return new_dict
end

---@param hauler_id HaulerId
function gui.hauler_manual_mode_changed(hauler_id)
    for _, player_gui in pairs(storage.player_guis) do
        if player_gui.train then
            if player_gui.train.id == hauler_id then
                player_gui.elements.class_textbox.enabled = player_gui.train.manual_mode
                player_gui.elements.class_auto_assign_button.enabled = player_gui.train.manual_mode
            end
        end
    end
end

--------------------------------------------------------------------------------

function gui.register_event_handlers()
    gui.network_add_flib_handlers()
    gui.station_add_flib_handlers()
    gui.hauler_add_flib_handlers()

    script.on_event(defines.events.on_gui_opened, on_gui_opened)
    script.on_event(defines.events.on_gui_closed, on_gui_closed)

    flib_gui.handle_events()
end
