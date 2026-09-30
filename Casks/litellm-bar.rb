cask "litellm-bar" do
  version "0.2.0"
  sha256 "a1dcb714c44a9d887ce099d067b4cf7d04ea2049232e88814fb8064f6ed3271a"

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
