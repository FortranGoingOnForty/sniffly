cask "sniffly" do
  version "0.2.4"
  sha256 :no_check  # Will calculate actual SHA256 once DMG is hosted

  url "https://github.com/FortranGoingOnForty/sniffly/releases/download/v#{version}/Sniffly-#{version}-macOS.dmg"
  name "Sniffly"
  desc "Fast, visual disk space analyzer built with Fortran and GTK4"
  homepage "https://github.com/FortranGoingOnForty/sniffly"

  # No dependencies needed - all GTK4 libraries are bundled!
  app "Sniffly.app"

  zap trash: [
    "~/Library/Logs/Sniffly.log",
  ]
end
