# dmgbuild settings for Swoop.dmg (used by scripts/make_dmg.sh, which passes -D app=… -D background=…).
# Layout in points; it must match packaging/dmg/background.swift (window 600×360, icon size 112).
import os

app = defines["app"]  # noqa: F821 (provided by dmgbuild)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {
    os.path.basename(app): (160, 200),
    "Applications": (440, 200),
}
background = defines["background"]  # noqa: F821

window_rect = ((200, 120), (600, 360))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
arrange_by = None
hide_extension = [os.path.basename(app)]
