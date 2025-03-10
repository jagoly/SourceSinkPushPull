-- SSPP by jagoly

--------------------------------------------------------------------------------

---@param base_type string
---@param short_name string
---@return data.CombinatorPrototype
local function generate_io_entity(base_type, short_name)
    local base = data.raw[base_type][base_type] --[[@as data.CombinatorPrototype]]
    local full_name = "sspp-" .. short_name .. "-io"

    ---@type data.CombinatorPrototype
    return {
        sprites = make_4way_animation_from_spritesheet({
            layers = {
                {
                    scale = 0.5,
                    filename = "__SourceSinkPushPull__/graphics/entity/io/" .. short_name .. ".png",
                    width = 154,
                    height = 160,
                    shift = util.by_pixel(1.0, -1.0),
                },
                {
                    scale = 0.5,
                    filename = "__SourceSinkPushPull__/graphics/entity/io/shadow.png",
                    width = 134,
                    height = 94,
                    shift = util.by_pixel(8.0, 7.0),
                    draw_as_shadow = true,
                },
            },
        }),
        activity_led_sprites = {
            north = util.draw_as_glow({
                scale = 0.5,
                filename = "__base__/graphics/entity/combinator/activity-leds/selector-combinator-LED-N.png",
                width = 16,
                height = 14,
                shift = util.by_pixel(7.5, -14.0 + 5.5),
            }),
            east = util.draw_as_glow({
                scale = 0.5,
                filename = "__base__/graphics/entity/combinator/activity-leds/selector-combinator-LED-E.png",
                width = 16,
                height = 16,
                shift = util.by_pixel(15.0 - 8.0, -3.0),
            }),
            south = util.draw_as_glow({
                scale = 0.5,
                filename = "__base__/graphics/entity/combinator/activity-leds/selector-combinator-LED-S.png",
                width = 16,
                height = 16,
                shift = util.by_pixel(-6.0, 7.5 - 5.5),
            }),
            west = util.draw_as_glow({
                scale = 0.5,
                filename = "__base__/graphics/entity/combinator/activity-leds/selector-combinator-LED-W.png",
                width = 14,
                height = 14,
                shift = util.by_pixel(-14.0 + 8.0, -13.5),
            }),
        },

        input_connection_points = {
            {
                shadow = { red = util.by_pixel(2, 25 - 5.5), green = util.by_pixel(21, 25 - 5.5) },
                wire = { red = util.by_pixel(-9, 16 - 5.5), green = util.by_pixel(9, 16 - 5.5) },
            },
            {
                shadow = { red = util.by_pixel(38 + 8.0, -2), green = util.by_pixel(-12 + 8.0, 12) },
                wire = { red = util.by_pixel(-24 + 8.0, -11), green = util.by_pixel(-23 + 8.0, 3) },
            },
            {
                shadow = { red = util.by_pixel(20, -13 + 5.5), green = util.by_pixel(1, -13 + 5.5) },
                wire = { red = util.by_pixel(9, -22 + 5.5), green = util.by_pixel(-9, -22 + 5.5) },
            },
            {
                shadow = { red = util.by_pixel(35 - 8.0, 13), green = util.by_pixel(35 - 8.0, -2) },
                wire = { red = util.by_pixel(23 - 8.0, 4), green = util.by_pixel(23 - 8.0, -11) },
            },
        },
        output_connection_points = {
            {
                shadow = { red = util.by_pixel(5, -11 + 5.5), green = util.by_pixel(20, -11 + 5.5) },
                wire = { red = util.by_pixel(-7, -22 + 5.5), green = util.by_pixel(7, -21 + 5.5) },
            },
            {
                shadow = { red = util.by_pixel(-12 - 8.0, -2), green = util.by_pixel(37 - 8.0, 12) },
                wire = { red = util.by_pixel(24 - 8.0, -12), green = util.by_pixel(24 - 8.0, 1) },
            },
            {
                shadow = { red = util.by_pixel(20, 28 - 5.5), green = util.by_pixel(5, 28 - 5.5) },
                wire = { red = util.by_pixel(7, 19 - 5.5), green = util.by_pixel(-7, 19 - 5.5) },
            },
            {
                shadow = { red = util.by_pixel(-10 + 8.0, 12), green = util.by_pixel(-10 + 8.0, -1) },
                wire = { red = util.by_pixel(-24 + 8.0, 1), green = util.by_pixel(-24 + 8.0, -12) },
            },
        },

        type = base_type,
        name = full_name,
        icon = "__SourceSinkPushPull__/graphics/icons/" .. full_name .. ".png",
        flags = { "placeable-neutral", "player-creation" },
        minable = { mining_time = 0.1, result = full_name },
        max_health = 150,
        corpse = "constant-combinator-remnants",
        dying_explosion = "constant-combinator-explosion",
        collision_box = { { -0.35, -0.35 }, { 0.35, 0.35 } },
        selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
        collision_mask = base.collision_mask,
        damaged_trigger_effect = base.damaged_trigger_effect,
        energy_source = { type = "void" },
        active_energy_usage = "1W",
        open_sound = { filename = "__base__/sound/open-close/train-stop-open.ogg", volume = 0.6 },
        activity_led_light_offsets = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
        screen_light_offsets = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
        input_connection_bounding_box = { { -0.5, 0.0 }, { 0.5, 0.5 } },
        output_connection_bounding_box = { { -0.5, -0.5 }, { 0.5, 0.0 } },
        circuit_wire_max_distance = combinator_circuit_wire_max_distance,
        allow_copy_paste = false,
    }
end

stop_entity = flib.copy_prototype(data.raw["train-stop"]["train-stop"], "sspp-stop") --[[@as data.TrainStopPrototype]]
stop_entity.icon = "__SourceSinkPushPull__/graphics/icons/sspp-stop.png"
stop_entity.allow_copy_paste = false

general_io_entity = generate_io_entity("decider-combinator", "general") --[[@as data.DeciderCombinatorPrototype]]
provide_io_entity = generate_io_entity("arithmetic-combinator", "provide") --[[@as data.ArithmeticCombinatorPrototype]]
request_io_entity = generate_io_entity("arithmetic-combinator", "request") --[[@as data.ArithmeticCombinatorPrototype]]

---@type data.ArithmeticCombinatorPrototype
hidden_io_entity = {
    sprites = { filename = "__SourceSinkPushPull__/graphics/invisible.png", width = 1, height = 1 },
    activity_led_sprites = { filename = "__SourceSinkPushPull__/graphics/invisible.png", width = 1, height = 1 },

    input_connection_points = {
        { wire = { 0, 0 }, shadow = { 0, 0 } },
        { wire = { 0, 0 }, shadow = { 0, 0 } },
        { wire = { 0, 0 }, shadow = { 0, 0 } },
        { wire = { 0, 0 }, shadow = { 0, 0 } },
    },
    output_connection_points = {
        { wire = { 0, 0 }, shadow = { 0, 0 } },
        { wire = { 0, 0 }, shadow = { 0, 0 } },
        { wire = { 0, 0 }, shadow = { 0, 0 } },
        { wire = { 0, 0 }, shadow = { 0, 0 } },
    },

    type = "arithmetic-combinator",
    name = "sspp-hidden-io",
    flags = { "placeable-off-grid", "not-on-map", "hide-alt-info" },
    collision_mask = { layers = {} },
    energy_source = { type = "void" },
    active_energy_usage = "1W",
    activity_led_light_offsets = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
    screen_light_offsets = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
    input_connection_bounding_box = { { 0, 0 }, { 0, 0 } },
    output_connection_bounding_box = { { 0, 0 }, { 0, 0 } },
}
