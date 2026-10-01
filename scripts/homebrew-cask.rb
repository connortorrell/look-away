# The starting point for Casks/look-away.rb in connortorrell/homebrew-tap.
# Copy it there once; after that the release workflow rewrites `version` and
# `sha256` on every release.
cask "look-away" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/connortorrell/look-away/releases/download/v#{version}/LookAway.dmg"
  name "Look Away"
  desc "Menu bar reminder for the 20/20/20 eye-strain rule"
  homepage "https://github.com/connortorrell/look-away"

  # Look Away updates itself from the menu.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Look Away.app"

  uninstall quit: "com.connortorrell.LookAway"

  zap trash: [
    "~/Library/Logs/Look Away",
    "~/Library/Preferences/com.connortorrell.LookAway.plist",
  ]
end
