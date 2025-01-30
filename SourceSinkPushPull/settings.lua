-- SSPP by jagoly

data:extend({
    ---@type data.ModBoolSettingPrototype
    {
        type = "bool-setting",
        name = "sspp-auto-paint-trains",
        order = "aa",
        setting_type = "runtime-global",
        default_value = true,
    },
    ---@type data.ModColorSettingPrototype
    {
        type = "color-setting",
        name = "sspp-depot-color",
        order = "ba",
        setting_type = "runtime-global",
        default_value = { 255, 255, 255 },
    },
    ---@type data.ModColorSettingPrototype
    {
        type = "color-setting",
        name = "sspp-fuel-color",
        order = "bb",
        setting_type = "runtime-global",
        default_value = { 0, 0, 0 },
    },
    ---@type data.ModColorSettingPrototype
    {
        type = "color-setting",
        name = "sspp-provide-color",
        order = "bc",
        setting_type = "runtime-global",
        default_value = { 0, 255, 0 },
    },
    ---@type data.ModColorSettingPrototype
    {
        type = "color-setting",
        name = "sspp-request-color",
        order = "bd",
        setting_type = "runtime-global",
        default_value = { 255, 0, 0 },
    },
    ---@type data.ModColorSettingPrototype
    {
        type = "color-setting",
        name = "sspp-liquidate-color",
        order = "be",
        setting_type = "runtime-global",
        default_value = { 0, 0, 255 },
    },
    ---@type data.ModIntSettingPrototype
    {
        type = "int-setting",
        name = "sspp-stations-per-tick",
        order = "ca",
        setting_type = "runtime-global",
        default_value = 2,
        minimum_value = 1,
        maximum_value = 8,
    },
})
