#!/usr/bin/env python3

import os
import json
import yaml
import glob
import subprocess

from libqtile import bar, layout, widget, hook
from libqtile.config import Click, Drag, Group, Key, Match, \
    Screen, ScratchPad, DropDown
from libqtile.lazy import lazy
from libqtile.utils import guess_terminal
from libqtile.extension import DmenuRun, J4DmenuDesktop


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
margin_width = 7
browser = "firefox"
file_manager = "thunar"
terminal = guess_terminal()
bar_font = "Cascadia Code Bold"


red = get_color("normal", "red", default="#B90E0A")
blue = get_color("normal", "blue", default="#0000CD")
gray = get_color("bright", "black", default="#484848")
green = get_color("normal", "green", default="#02911F")
yellow = get_color("normal", "yellow", default="#FEBE00")
magenta = get_color("normal", "magenta", default="#02911F")
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
    Key([mod], "z", lazy.layout.normalize(), desc="Reset all window sizes"),
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
    Key([mod], "n", lazy.spawn(file_manager), desc="Open a file manager"),
    # Screenshots
    Key([], "Print", lazy.spawn("sleep 1 && scrot ~/Pictures/Screenshot-$(date +%F_%T).png", shell=True)),
    Key([mod], "Print", lazy.spawn("scrot -s ~/Pictures/Screenshot-$(date +%F_%T).png", shell=True)),
    # Utilities
    Key([mod], "l", lazy.spawn("slock"), desc="Lock the screen"),
    Key([mod], "p", lazy.group["scratchpad"].dropdown_toggle("power menu")),
    Key([mod], "d", lazy.group["scratchpad"].dropdown_toggle("app launcher")),
    Key([mod], "h", lazy.group["scratchpad"].dropdown_toggle("dark theme")),
    Key([mod, "shift"], "h", lazy.group["scratchpad"].dropdown_toggle("light theme")),
    Key([mod], "k", lazy.group["scratchpad"].dropdown_toggle("pick wallpaper"))
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
        ("pick wallpaper", "set-wallpaper"),
        ("power menu", "open-powermenu"),
        ("app launcher", "gyr")
    ]
]))


layout_settings={
    "border_focus": yellow,
    "border_normal": blue,
    "border_width": border_width,
    "margin": margin_width,
}
layouts = [
    layout.Bsp(**layout_settings),
    layout.Max(),
    layout.MonadTall(**layout_settings),
    layout.MonadThreeCol(**layout_settings),
]


widget_defaults = dict(
    font=bar_font,
    foreground=foreground_color,
    fontsize=16,
    padding_x=5,
    padding_y=12,
)
extension_defaults = widget_defaults.copy()


wallpaper = next(glob.iglob(os.path.expanduser("~/.wallpaper")), None)
wallpaper_config = { "wallpaper": wallpaper, "wallpaper_mode": "fill" } if wallpaper else {}
backlight_name = next((card.rsplit("/")[-1] for card in glob.iglob("/sys/class/backlight/*")), None)
has_battery = len(glob.glob("/sys/class/power_supply/*")) > 0
screens = [
    Screen(
        bottom=bar.Bar(
            [
                widget.CurrentLayout(),
                widget.GroupBox(
                    active=yellow,
                    inactive=blue,
                    urgent_text=red,
                    highlight_color=gray,
                    highlight_method="line",
                    this_current_screen_border=yellow,
                ),
                widget.Prompt(foreground=green),
                widget.WindowName(),
                widget.PulseVolume(foreground=magenta),
                widget.Backlight(foreground=yellow, backlight_name=backlight_name)
                    if backlight_name else widget.Spacer(length=0),
                widget.Battery(foreground=green, format="{char} {percent:2.0%} {hour:d}:{min:02d}")
                    if has_battery else widget.Spacer(length=0),
                widget.Clock(format="%Y-%m-%d %a %I:%M %p"),
                widget.Systray(),
            ],
            32,
            margin=margin_width,
            background=background_color,
        ),
        **wallpaper_config,
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
cursor_warp = True
floating_layout = layout.Floating(
    border_focus=magenta,
    border_normal=green,
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
    home = os.path.expanduser("~/.config/qtile/autostart.sh")
    subprocess.Popen([home])
