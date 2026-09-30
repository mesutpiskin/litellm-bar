cask "litellm-bar" do
  version "0.1.0"
  sha256 "c1a712b0b2deb45b686f4a40b11fe7a531b979379b6f26fbb569ff49cee0a911"

  url "https://github.com/mesutpiskin/litellm-bar/releases/download/v#{version}/LiteLLMBar-#{version}.zip"
  name "LiteLLM Bar"
  desc "Menu bar app to view LiteLLM model, token and spend usage"
  homepage "https://github.com/mesutpiskin/litellm-bar"

  depends_on macos: ">= :ventura"

  app "LiteLLMBar.app"

  # The app is ad-hoc signed (not notarized); drop the quarantine flag so Gatekeeper lets it open.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/LiteLLMBar.app"],
                   sudo: false
  end

  uninstall quit: "com.mesutpiskin.litellmbar"

  zap trash: [
    "~/Library/Preferences/com.mesutpiskin.litellmbar.plist",
  ]
end
