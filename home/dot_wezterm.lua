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

local config = wezterm.config_builder()

local is_windows = wezterm.target_triple:find("windows") ~= nil

-- ── Updates ──────────────────────────────────────────────────────────────────

config.check_for_updates = true

-- ── Font ─────────────────────────────────────────────────────────────────────

config.font_size = 12
config.font = wezterm.font_with_fallback({
	{ family = "CaskaydiaMono Nerd Font", weight = "Regular" },
})
config.line_height = 1.0

-- ── Appearance ────────────────────────────────────────────────────────────────

config.color_scheme = "Catppuccin Mocha"
config.set_environment_variables = {
	BAT_THEME = "Catppuccin Mocha",
}

config.inactive_pane_hsb = { saturation = 0.95, brightness = 0.95 }

config.window_background_opacity = 0.6
config.text_background_opacity = 0.95
if is_windows then
	config.win32_system_backdrop = "Acrylic"
end

config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }

config.window_frame = {
	font = wezterm.font({ family = "Segoe UI", weight = "Bold" }),
	font_size = 12,
	active_titlebar_bg = "#f3f3f3",
	inactive_titlebar_bg = "#ececec",
}

config.integrated_title_button_color = "Auto"

config.colors = {
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
	selection_bg = "rgba(137,180,250,0.35)",
}

-- ── Window ────────────────────────────────────────────────────────────────────

config.initial_cols = 120
config.initial_rows = 30

config.adjust_window_size_when_changing_font_size = false
config.window_close_confirmation = "NeverPrompt"
config.enable_scroll_bar = true

-- ── Tab bar ───────────────────────────────────────────────────────────────────

config.enable_tab_bar = true
config.use_fancy_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false
config.show_new_tab_button_in_tab_bar = true

-- ── Cursor ────────────────────────────────────────────────────────────────────

config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 500
config.animation_fps = 60

-- ── Status bar ────────────────────────────────────────────────────────────────

config.status_update_interval = 1000

-- ── Domains ───────────────────────────────────────────────────────────────────

if is_windows then
	config.wsl_domains = wezterm.default_wsl_domains()
	config.default_domain = "WSL:Ubuntu"

	config.launch_menu = {
		{
			label = "PowerShell",
			domain = { DomainName = "local" },
			args = { "pwsh", "-NoLogo" },
		},
	}
	-- One entry per installed distro; Docker Desktop's distros are not shells.
	for _, domain in ipairs(config.wsl_domains) do
		if not domain.distribution:find("^docker") then
			table.insert(config.launch_menu, {
				label = domain.distribution,
				domain = { DomainName = domain.name },
			})
		end
	end
end

-- Clusters: ssh inside WSL on Windows, because Windows OpenSSH cannot
-- multiplex and WSL's ControlMaster lets later tabs skip the Duo prompt.
config.launch_menu = config.launch_menu or {}
for _, host in ipairs({ "sherlock", "marlowe" }) do
	local entry = { label = host:sub(1, 1):upper() .. host:sub(2), args = { "ssh", host } }
	if is_windows then
		entry.domain = { DomainName = "WSL:Ubuntu" }
	end
	table.insert(config.launch_menu, entry)
end

-- ── Key bindings ──────────────────────────────────────────────────────────────

config.treat_left_ctrlalt_as_altgr = false

-- Split the active pane in its own domain and directory (reported with OSC 7).
-- The new pane runs that domain's default program, not a copy of the pane's
-- command: an ssh launcher tab splits into that domain's shell (WSL on
-- Windows, the local shell elsewhere), not a second ssh. On Windows the local
-- domain's default is %ComSpec% (cmd.exe), so a local pane's split names pwsh
-- here. config.default_prog cannot do this: `wezterm start --cwd <dir>`
-- without a program (Explorer's "Open WezTerm here") builds its command from
-- it before picking the default WSL domain, and pwsh does not exist there.
local function split_pane(direction)
	return wezterm.action_callback(function(window, pane)
		local args = nil
		if is_windows and pane:get_domain_name() == "local" then
			args = { "pwsh", "-NoLogo" }
		end
		window:perform_action(
			act.SplitPane({ direction = direction, command = { domain = "CurrentPaneDomain", args = args } }),
			pane
		)
	end)
end
local split_right, split_down = split_pane("Right"), split_pane("Down")

config.keys = {
	{
		key = "w",
		mods = "ALT",
		action = act.CloseCurrentTab({ confirm = false }),
	},
	{
		key = "l",
		mods = "ALT",
		action = act.ShowLauncherArgs({ flags = "LAUNCH_MENU_ITEMS" }),
	},
	-- Jump between prompts marked by OSC 133 (Powerlevel10k and the
	-- oh-my-posh theme emit them), as Ctrl+Up/Down does in Windows Terminal.
	{ key = "UpArrow", mods = "CTRL", action = act.ScrollToPrompt(-1) },
	{ key = "DownArrow", mods = "CTRL", action = act.ScrollToPrompt(1) },
	-- Windows Terminal's split key, splitting to the right. Ctrl+Shift+Z
	-- already zooms a pane.
	{ key = "D", mods = "ALT|SHIFT", action = split_right },
	-- WezTerm's own split keys, Ctrl+Shift+Alt+% (right) and Ctrl+Shift+Alt+"
	-- (down), rebound in every form its defaults register (which form a press
	-- resolves to depends on platform and layout; on Windows with a US layout
	-- it is the shifted % and "), so none of them falls back to cmd.exe.
	{ key = "5", mods = "CTRL|SHIFT|ALT", action = split_right },
	{ key = "%", mods = "CTRL|SHIFT|ALT", action = split_right },
	{ key = "%", mods = "CTRL|ALT", action = split_right },
	{ key = "'", mods = "CTRL|SHIFT|ALT", action = split_down },
	{ key = '"', mods = "CTRL|SHIFT|ALT", action = split_down },
	{ key = '"', mods = "CTRL|ALT", action = split_down },
}

if is_windows then
	table.insert(config.keys, {
		key = "p",
		mods = "CTRL|ALT",
		action = act.SpawnCommandInNewTab({
			domain = { DomainName = "local" },
			args = { "pwsh", "-NoLogo" },
		}),
	})
	table.insert(config.keys, {
		key = "u",
		mods = "CTRL|ALT",
		action = act.SpawnTab({ DomainName = "WSL:Ubuntu" }),
	})
end

config.mouse_bindings = {
	{
		event = { Down = { streak = 1, button = "Right" } },
		mods = "NONE",
		action = act.PasteFrom("Clipboard"),
	},
}

-- ── Events ────────────────────────────────────────────────────────────────────

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
		{ Foreground = { Color = "#cba6f7" } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = "  " .. table.concat(cells, "   ") .. "  " },
	}))
end)

-- ── Return ────────────────────────────────────────────────────────────────────

return config
