--
-- ██╗    ██╗███████╗███████╗████████╗███████╗██████╗ ███╗   ███╗
-- ██║    ██║██╔════╝╚══███╔╝╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
-- ██║ █╗ ██║█████╗    ███╔╝    ██║   █████╗  ██████╔╝██╔████╔██║
-- ██║███╗██║██╔══╝   ███╔╝     ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║
-- ╚███╔███╔╝███████╗███████╗   ██║   ███████╗██║  ██║██║ ╚═╝ ██║
--  ╚══╝╚══╝ ╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝
-- A GPU-accelerated cross-platform terminal emulator
-- https://wezfurlong.org/wezterm/

local wezterm = require("wezterm")

local act = wezterm.action

local config = {
    check_for_updates = true,
    font_size = 12,
    font = wezterm.font_with_fallback({
        { family = "CaskaydiaMono Nerd Font", weight = "Regular" },
    }),
    line_height = 1.0,

    color_scheme = "Catppuccin Mocha",
    set_environment_variables = {
        BAT_THEME = "Catppuccin-mocha",
    },

    inactive_pane_hsb = { saturation = 0.95, brightness = 0.95 },

    initial_cols = 120,
    initial_rows = 30,

    adjust_window_size_when_changing_font_size = false,
    window_close_confirmation = "NeverPrompt",
    window_background_opacity = 0.6,
    text_background_opacity = 0.95,
    win32_system_backdrop = "Acrylic",

    window_decorations = "INTEGRATED_BUTTONS|RESIZE",

    enable_tab_bar = true,
    use_fancy_tab_bar = true,
    hide_tab_bar_if_only_one_tab = false,
    show_new_tab_button_in_tab_bar = true,

    default_cursor_style = 'BlinkingBar',
    cursor_blink_rate = 500,
    animation_fps = 60,

    wsl_domains = wezterm.default_wsl_domains(),
    default_domain = 'WSL:Ubuntu',

    window_padding = { left = 0, right = 0, top = 0, bottom = 0 },
    enable_scroll_bar = true,

    status_update_interval = 1000,

    window_frame = {
        font = wezterm.font { family = "Segoe UI", weight = "Bold" },
        font_size = 12,
        active_titlebar_bg = "#f3f3f3",
        inactive_titlebar_bg = "#ececec",
    },

    integrated_title_button_color = "Auto",

    colors = {
        tab_bar = {
            inactive_tab_edge = "#d3d3d3",

            active_tab = {
                bg_color = "#ffffff",
                fg_color = "#1f1f1f",
                intensity = "Bold",
            },
            inactive_tab = {
                bg_color = "#eaeaea",
                fg_color = "#4b4b4b",
                intensity = "Normal",
            },
            inactive_tab_hover = {
                bg_color = "#e0e0e0",
                fg_color = "#202020",
                italic = true,
            },
            new_tab = {
                bg_color = "#efefef",
                fg_color = "#6a6a6a",
            },
            new_tab_hover = {
                bg_color = "#e0e0e0",
                fg_color = "#202020",
                italic = true,
            },
        },
        selection_fg = "none",
        selection_bg = "rgba(203,166,247,0.35)",
    },

    launch_menu = {
        {
            label = "PowerShell",
            domain = { DomainName = "local" },
            args = { "pwsh", "-NoLogo" }
        },
        {
            label = "Ubuntu",
            domain = { DomainName = "WSL:Ubuntu" }
        },
        {
            label = "Debian",
            domain = { DomainName = "WSL:Debian" },
        },
    },

    treat_left_ctrlalt_as_altgr = false,

    keys = {
        {
            key = "p",
            mods = "CTRL|ALT",
            action = act.SpawnCommandInNewTab {
                domain = { DomainName = "local" },
                args = { "pwsh", "-NoLogo" },
            },
        },
        {
            key = "u",
            mods = "CTRL|ALT",
            action = act.SpawnTab { DomainName = "WSL:Ubuntu" },
        },
        {
            key = "d",
            mods = "CTRL|ALT",
            action = act.SpawnTab { DomainName = "WSL:Debian" },
        },
        {
            key = "w",
            mods = "ALT",
            action = act.CloseCurrentTab { confirm = false },
        },
        {
            key = "l",
            mods = "ALT",
            action = act.ShowLauncherArgs { flags = "LAUNCH_MENU_ITEMS" },
        }
    },
    mouse_bindings = {
        {
            event = { Down = { streak = 1, button = "Right" } },
            mods = "NONE",
            action = act({ PasteFrom = "Clipboard" }),
        },
    }

}

local function titlebar_bg_for_focus(window)
    local ef = window:effective_config()
    local wf = ef.window_frame or {}
    if window:is_focused() then
        return wf.active_titlebar_bg or "#f3f3f3"
    else
        return wf.inactive_titlebar_bg or "#ececec"
    end
end

wezterm.on("update-status", function(window, pane)
    local cells = {}
    table.insert(cells, "  " .. (window:active_workspace() or "default"))
    table.insert(cells, "  " .. (pane:get_domain_name() or "local"))
    table.insert(cells, "  " .. wezterm.strftime("%a %b %-d  %H:%M"))

    window:set_right_status(wezterm.format({
        "ResetAttributes",
        { Background = { Color = titlebar_bg_for_focus(window) } },
        { Foreground = { Color = "#f5c2e7" } },
        { Attribute = { Intensity = "Bold" } },
        { Text = "  " .. table.concat(cells, "   ") .. "  " },
    }))
end)


return config
