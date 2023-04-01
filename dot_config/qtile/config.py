#!/usr/bin/env python3

import os
import json
import yaml
import subprocess

from libqtile import bar, layout, widget, hook
from libqtile.config import Click, Drag, Group, Key, Match, \
    Screen, ScratchPad, DropDown
from libqtile.lazy import lazy
from libqtile.utils import guess_terminal
from libqtile.extension import DmenuRun


def get_chezmoi_data(*path: str, default=None):
    try:
        process = subprocess.run(["chezmoi", "data"], capture_output=True)
        data = json.loads(process.stdout.decode("utf-8"))
        for segment in path:
            data = data[segment]
        return data
    except:
        return default


def get_color(*path: str, default: str) -> str:
    try:
        with open(os.path.expanduser("~/.theme.yml"), "r") as f:
            data = yaml.safe_load(f)["colors"]
            for segment in path:
                data = data[segment]
            return data
    except:
        pass
    return default


mod = "mod4"
border_width = 4
browser = "firefox"
terminal = guess_terminal()
terminal_font = get_chezmoi_data("terminalFont", default="sans")


normal_blue = get_color("normal", "blue", default="#0000CD")
bright_blue = get_color("bright", "blue", default="#87CEEB")
normal_yellow = get_color("normal", "yellow", default="#FEBE00")
normal_green = get_color("normal", "green", default="#02911F")
normal_magenta = get_color("normal", "magenta", default="#02911F")
normal_red = get_color("normal", "red", default="#B90E0A")
gray = get_color("bright", "black", default="#484848")
background_color = get_color("primary", "background", default="#000000")
foreground_color = get_color("primary", "foreground", default="#FFFFFF")


keys = [
    # Switch between windows
    Key([mod], "Left", lazy.layout.left(), desc="Move focus to left"),
    Key([mod], "Right", lazy.layout.right(), desc="Move focus to right"),
    Key([mod], "Down", lazy.layout.down(), desc="Move focus down"),
    Key([mod], "Up", lazy.layout.up(), desc="Move focus up"),
    Key([mod], "space", lazy.layout.next(), desc="Move window focus to other window"),
    # Move windows between left/right columns or move up/down in current stack.
    # Moving out of range in Columns layout will create new column.
    Key([mod, "shift"], "Left", lazy.layout.shuffle_left(), desc="Move window to the left"),
    Key([mod, "shift"], "Right", lazy.layout.shuffle_right(), desc="Move window to the right"),
    Key([mod, "shift"], "Down", lazy.layout.shuffle_down(), desc="Move window down"),
    Key([mod, "shift"], "Up", lazy.layout.shuffle_up(), desc="Move window up"),
    # Grow windows. If current window is on the edge of screen and direction
    # will be to screen edge - window would shrink.
    Key([mod, "control"], "Left", lazy.layout.grow_left(), desc="Grow window to the left"),
    Key([mod, "control"], "Right", lazy.layout.grow_right(), desc="Grow window to the right"),
    Key([mod, "control"], "Down", lazy.layout.grow_down(), desc="Grow window down"),
    Key([mod, "control"], "Up", lazy.layout.grow_up(), desc="Grow window up"),
    Key([mod], "n", lazy.layout.normalize(), desc="Reset all window sizes"),
    # Toggle between split and unsplit sides of stack.
    # Split = all windows displayed
    # Unsplit = 1 window displayed, like Max layout, but still with
    # multiple stack panes
    Key(
        [mod, "shift"],
        "Return",
        lazy.layout.toggle_split(),
        desc="Toggle between split and unsplit sides of stack",
    ),
    # Toggle between different layouts as defined below
    Key([mod], "Tab", lazy.next_layout(), desc="Toggle between layouts"),
    Key([mod], "q", lazy.window.kill(), desc="Kill focused window"),
    Key([mod, "control"], "r", lazy.reload_config(), desc="Reload the config"),
    Key([mod, "control"], "q", lazy.shutdown(), desc="Shutdown Qtile"),
    Key([mod], "r", lazy.spawncmd(), desc="Spawn a command using a prompt widget"),
    # Run applications
    Key([mod], "Return", lazy.spawn(terminal), desc="Launch terminal"),
    Key([mod], "b", lazy.spawn(browser), desc="Open a browser"),
    Key([mod], "d", lazy.run_extension(DmenuRun(
        dmenu_prompt=">",
        dmenu_bottom=True,
        dmenu_font=terminal_font,
        background=background_color,
        foreground=foreground_color,
        selected_background=normal_blue,
        selected_foreground=background_color,
    ))),
    # Utilities
    Key([mod], "l", lazy.spawn("slock"), desc="Lock the screen"),
    Key([mod], "p", lazy.group["scratchpad"].dropdown_toggle("power menu")),
    Key([mod], "h", lazy.group["scratchpad"].dropdown_toggle("dark theme")),
    Key([mod, "shift"], "h", lazy.group["scratchpad"].dropdown_toggle("light theme")),
]


groups = [Group(str(i)) for i in range(1, 10)]


for i in groups:
    keys.extend(
        [
            # mod1 + letter of group = switch to group
            Key([mod], i.name, lazy.group[i.name].toscreen(),
                desc=f"Switch to group {i.name}"),
            # mod1 + shift + letter of group = switch to & move focused window to group
            Key([mod, "shift"], i.name,
                lazy.window.togroup(i.name, switch_group=True),
                desc=f"Switch to & move focused window to group {i.name}"),
        ]
    )


groups.append(ScratchPad("scratchpad", [
    DropDown(
        command[0],
        f"alacritty -o window.padding.x=10 -o window.padding.y=10 \
          -o window.dynamic_padding=true -e fish -c '{command[1]}'",
        x=0.35, y=0.35, width=0.3, height=0.3)
    for command in [
        ("light theme", "set-theme light --select"),
        ("dark theme", "set-theme dark --select"),
        ("power menu", "open-powermenu")
    ]
]))


layout_settings={
    "border_focus": normal_yellow,
    "border_normal": normal_blue,
    "border_width": border_width,
    "margin": border_width*2,
}
layouts = [
    layout.Bsp(**layout_settings),
    layout.Max(),
    layout.MonadTall(**layout_settings),
    layout.MonadThreeCol(**layout_settings),
]


widget_defaults = dict(
    font=terminal_font,
    foreground=foreground_color,
    fontsize=15,
    padding=5,
)
extension_defaults = widget_defaults.copy()


screens = [
    Screen(
        wallpaper='~/.background.jpg',
        wallpaper_mode='fill',
        bottom=bar.Bar(
            [
                widget.CurrentLayout(),
                widget.GroupBox(
                    inactive=normal_blue,
                    urgent_text=normal_red,
                    highlight_color=gray,
                    highlight_method="line",
                    this_current_screen_border=normal_yellow,
                ),
                widget.Prompt(foreground=normal_blue),
                widget.WindowName(),
                widget.PulseVolume(foreground=normal_magenta),
                widget.Backlight(foreground=normal_yellow, backlight_name="intel_backlight"),
                widget.Battery(foreground=normal_green, format="{char} {percent:2.0%} {hour:d}:{min:02d}"),
                widget.Clock(format="%Y-%m-%d %a %I:%M %p"),
                widget.Systray(),
            ],
            24,
            background=background_color,
        ),
    ),
]


# Drag floating layouts
mouse = [
    Drag([mod], "Button1", lazy.window.set_position_floating(), start=lazy.window.get_position()),
    Drag([mod], "Button3", lazy.window.set_size_floating(), start=lazy.window.get_size()),
    Click([mod], "Button2", lazy.window.bring_to_front()),
]


dgroups_key_binder = None
dgroups_app_rules = []  # type: list
follow_mouse_focus = True
bring_front_click = False
cursor_warp = False
floating_layout = layout.Floating(
    border_focus=normal_magenta,
    border_normal=normal_green,
    border_width=border_width,
    float_rules=[
        # Run the utility of `xprop` to see the wm class and name of an X client.
        *layout.Floating.default_float_rules,
        Match(wm_class="confirmreset"),  # gitk
        Match(wm_class="makebranch"),  # gitk
        Match(wm_class="maketag"),  # gitk
        Match(wm_class="ssh-askpass"),  # ssh-askpass
        Match(title="branchdialog"),  # gitk
        Match(title="pinentry"),  # GPG key password entry
    ]
)


@hook.subscribe.startup_once
def autostart():
    home = os.path.expanduser('~/.config/qtile/autostart.sh')
    subprocess.Popen([home])
