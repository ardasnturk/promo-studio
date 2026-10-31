# Homebrew cask for Promo Studio.
#
#   brew tap ardasnturk/promo-studio https://github.com/ardasnturk/promo-studio
#   brew install --cask promo-studio
#
# `version` and `sha256` are updated by scripts/prepare-release.sh.
cask "promo-studio" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/ardasnturk/promo-studio/releases/download/v#{version}/PromoStudio-#{version}.dmg"
  name "Promo Studio"
  desc "Promo videos for your apps, written and directed by Claude Code"
  homepage "https://github.com/ardasnturk/promo-studio"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"

  app "Promo Studio.app"

  uninstall quit: "com.jastech.PromoStudio"

  zap trash: [
    "~/Library/Application Support/Promo Studio",
    "~/Library/Caches/com.jastech.PromoStudio",
    "~/Library/HTTPStorages/com.jastech.PromoStudio",
    "~/Library/Preferences/com.jastech.PromoStudio.plist",
    "~/Library/WebKit/com.jastech.PromoStudio",
  ]

  caveats <<~EOS
    Promo Studio needs Claude Code (signed in) and Node.js 20 or later on this
    Mac. On first launch a setup checklist shows what is missing and installs
    the Remotion video engine.
      https://github.com/ardasnturk/promo-studio/blob/main/docs/SETUP.md

    Secrets (Instagram tokens, Meta App Secret, Gemini key) live in your login
    keychain ("Promo Studio"); `brew uninstall --zap` does not remove them.
  EOS
end
