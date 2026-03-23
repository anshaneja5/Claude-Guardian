cask "claudeguardian" do
  version "1.0.4"
  sha256 "852fa0618e935c0daf133583982415ce980a8b3b79be118050019358c3e3b11d"

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

  preflight do
    # Run uninstall script to clean up hooks before the app is removed
    uninstall_script = "#{appdir}/ClaudeGuardian.app/Contents/Resources/uninstall.sh"
    system_command uninstall_script if File.exist?(uninstall_script)
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
