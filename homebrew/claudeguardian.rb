cask "claudeguardian" do
  version "1.0.2"
  sha256 "2bb8fe0c1e4ccba11a2330d5106b8df96a13b3d3e0b58ffde3f266e4f5949ad7"

  url "https://github.com/anshaneja5/Claude-Guardian/releases/download/v#{version}/ClaudeGuardian.zip"
  name "Claude Guardian"
  desc "Floating pixel-art mascot for Claude Code permissions"
  homepage "https://github.com/anshaneja5/Claude-Guardian"

  depends_on macos: ">= :ventura"

  app "ClaudeGuardian.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-cr", "#{appdir}/ClaudeGuardian.app"]
    system_command "#{appdir}/ClaudeGuardian.app/Contents/Resources/post-install.sh"
  end

  uninstall launchctl: "com.claudeguardian.app",
            quit:      "com.claudeguardian.app"

  zap trash: [
    "~/.config/claude-guardian",
    "~/Library/LaunchAgents/com.claudeguardian.app.plist",
    "/tmp/claude-guardian.log",
    "/tmp/claude-guardian.err",
  ]
end
