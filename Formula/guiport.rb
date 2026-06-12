# Homebrew formula for guiport.
#
# Distribution model: a tap repository at edihasaj/homebrew-guiport hosts this file.
# Until tagged releases exist, this formula builds from the main branch.
#
# Once a release is cut:
#   - Replace `head` with `url` + `sha256` pointing at the release tarball.
#   - Bump `version`.
#
class Guiport < Formula
  desc "Fast CLI/MCP control layer for desktop apps. Built for coding agents."
  homepage "https://github.com/edihasaj/guiport"
  license "MIT"
  head "https://github.com/edihasaj/guiport.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :ventura

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/guiport"
  end

  def caveats
    <<~EOS
      guiport needs two macOS permissions to function:

        1. Accessibility   — System Settings → Privacy & Security → Accessibility
        2. Screen Recording — System Settings → Privacy & Security → Screen Recording

      Run `guiport doctor --fix` first. It registers ~/Applications/guiport.app
      so macOS shows a real `guiport` app entry in the permission lists.

      After granting, verify with:

        guiport doctor
    EOS
  end

  test do
    assert_match "guiport", shell_output("#{bin}/guiport --version")
  end
end
