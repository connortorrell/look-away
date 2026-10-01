# dmgbuild settings for LookAway.dmg. scripts/package-release.sh runs:
#
#   dmgbuild -s scripts/dmg-settings.py -D app="build/Look Away.app" "Look Away" dist/LookAway.dmg
#
# The positions below match the arrow drawn in Resources/Artwork/dmg-background.svg.
import os.path

application = defines["app"]  # noqa: F821
appname = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}

icon = "Resources/AppIcon.icns"
# dmgbuild finds dmg-background@2x.png beside it and combines the two.
background = "Resources/dmg-background.png"

window_rect = ((200, 120), (600, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
icon_locations = {appname: (150, 180), "Applications": (450, 180)}
