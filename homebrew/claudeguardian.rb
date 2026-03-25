cask "claudeguardian" do
  version "2.1.1"
  sha256 "f485ec9aa20745d9257d7d23dff23b61c92d03c7c3f9ceba5eb100bb68897047"

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
