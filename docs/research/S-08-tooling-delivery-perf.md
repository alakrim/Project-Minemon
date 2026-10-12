# S-08 — Tooling, delivery and performance (2026-10-10; saved by Opus from the scout's hand-back)

## Findings
- **Launcher:**
  - Modrinth App (instances under `%AppData%\ModrinthApp\profiles\`, or under `%AppData%\ModrinthApp\` in general) installs a .mrpack in one click and supports shared instances for friends.
  - Prism keeps instances under `%APPDATA%\PrismLauncher\instances\`.
- **Global datapacks:** Global Datapacks (LGPL-3; it puts packs in `.minecraft/datapacks`, though 1.21.1 support is unverified) or Paxi (`config/paxi/datapacks`). Pack format for 1.21.1 is 48.
- **Offline validation, tested here:**
  - `mecha -m 1.21` (PyPI) catches .mcfunction syntax errors (it stops at the first error per file);
  - Python json catches broken JSON;
  - nbtlib checks SNBT;
  - molang (npm, last release 2022) parses MoLang.
  - Spyglass runs headless but has no vanilla data (api.spyglassmc.com is blocked), so it reports nothing.
- **Performance stack:** Sodium, Iris, Lithium, FerriteCore, ModernFix, ImmediatelyFast, EntityCulling; Java 21; about a 3 GB heap; 6-chunk render distance.
- **Shaders:** Complementary Reimagined Potato or Sildur's Enhanced Default first (very low cost). Install them through the launcher, not bundled (licences).
- **Friends:** a Modrinth shared instance, plus e4mc (only the host installs it) or Essential. Untested with Cobblemon.
- **Android:** Zalith Launcher 2 is an unofficial, play-only route; out of scope.

## Recommendation
- Modrinth App with the Fabric 1.21.1 Cobblemon base.
- Deliver our text layer into the world's or instance's datapacks folder.
- Validate with mecha, json and nbtlib.
- Allocate 3 GB of RAM and start with the Potato shaders.

## Confidence
- High for the validation results (run here).
- Medium for paths and licences.
- Low for Vega 8 performance.

## Sources
support.modrinth.com storage article; prismlauncher.org wiki; Modrinth pages for Iris, Sodium, Lithium, FerriteCore, ModernFix, ImmediatelyFast, EntityCulling, Better Leaves and Fresh Animations; the Complementary licence; github.com/ZalithLauncher2; pypi.org (mecha, nbtlib); npmjs.com (molang, @spyglassmc/language-server)

## Open questions
- Does Global Datapacks support 1.21.1?
- Do Essential or e4mc work with Cobblemon?
- Real fps on the Vega 8.
