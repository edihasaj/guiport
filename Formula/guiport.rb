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
    # Wrap the CLI in a guiport.app and run bin/guiport from inside it, so macOS
    # shows the real logo in the Privacy panes and keys the TCC grant to a stable
    # identity across upgrades (issue #4). `head` builds are ad-hoc signed;
    # tagged releases ship a Developer-ID-signed bundle from the tap.
    system "scripts/make-app-bundle.sh",
           "--bin", ".build/release/guiport",
           "--out", "#{prefix}/guiport.app"
    bin.install_symlink prefix/"guiport.app/Contents/MacOS/guiport" => "guiport"
    pkgshare.install "assets/icon.icns"
  end

  def caveats
    <<~EOS
      guiport needs two macOS permissions to function:

        1. Accessibility   — System Settings → Privacy & Security → Accessibility
        2. Screen Recording — System Settings → Privacy & Security → Screen Recording

      This install ships a signed guiport.app and runs the CLI from inside it,
      so the permission lists show guiport's real logo. Run `guiport doctor --fix`
      to trigger both prompts, then toggle guiport ON.

      After granting, verify with:

        guiport doctor
    EOS
  end

  test do
    assert_match "guiport", shell_output("#{bin}/guiport --version")
  end
end
