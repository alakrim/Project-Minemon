# S-04: Species data and free assets

## Findings
- **PokeAPI `data/v2/csv`**: software BSD-3-Clause; data has no explicit licence. Covers all 251 species: stats, types, evolutions, egg groups, rates, learnsets per version group, moves. Sprite and cry repos are separate and not used. Flavour text is Game Freak prose; excluded.
- **Pokémon Showdown `data/`**: MIT server; data files carry no separate notice. Compact TypeScript; learnset codes like `4L1`. Gen 2 overrides in `data/mods/gen2`.
- **Veekun, Bulbapedia**: avoid. Veekun data is game-extracted ("at your own legal risk"); Bulbapedia is CC BY-NC-SA 2.5.
- **Assets**: Kenney and OpenGameArt CC0 cover textures, UI, SFX and fonts. Quaternius forbids standalone redistribution. Pixel Perfection is share-alike (CC BY-SA 4.0). Freesound needs a per-clip CC0 filter.

## Recommendation
- **Data**: PokeAPI CSVs as primary. A one-off script keeps species 1-251, drops flavour, sprite and cry fields, and writes committed JSON species packs. Cross-check Gen 2 learnsets and values against Showdown.
- **Assets**: Kenney and OpenGameArt CC0 first; Press Start 2P (OFL 1.1) for the pixel font.
- **Stand-in creatures**: Blockbench or parametric generation; export glTF 2.0 (.glb) for Godot 4.

## Confidence
- High: licences of PokeAPI, Showdown, Veekun, Bulbapedia, Kenney, OpenGameArt block set, Press Start 2P, Pixel Perfection, Blockbench.
- Medium: PokeAPI data licence (no explicit statement); Quaternius and Poly Pizza terms.
- Low: Blockbench export list and Godot import formats (docs fetch failed; from background knowledge).

## Sources
- https://github.com/PokeAPI/pokeapi (LICENSE.md via raw.githubusercontent.com)
- https://github.com/smogon/pokemon-showdown
- https://github.com/veekun/pokedex
- https://bulbapedia.bulbagarden.net/wiki/Bulbapedia:Copyrights
- https://kenney.nl/support
- https://opengameart.org/content/16x16-block-texture-set
- https://opengameart.org/content/cc0-sounds-library
- https://freesound.org/help/faq/
- https://quaternius.com/ (license page not fetched; see table)
- https://modrinth.com/project/JTabr6nO
- https://raw.githubusercontent.com/google/fonts/main/ofl/pressstart2p/OFL.txt
- https://github.com/JannisX11/blockbench
- https://incompetech.com/music/royalty-free/licenses/
- https://poly.pizza/docs/tos

## Source and licence table
| Source | Licence | Use |
|---|---|---|
| PokeAPI `data/v2/csv` | BSD-3-Clause (code); data not explicit | Primary species and move data |
| Pokémon Showdown `data/` | MIT (repo); no data notice | Cross-check learnsets, Gen 2 mods |
| Veekun pokedex | MIT code; game-extracted data | Avoid |
| Bulbapedia | CC BY-NC-SA 2.5 | Avoid copying |
| Kenney.nl | CC0 | UI, SFX, fonts, models |
| OpenGameArt "16x16 block texture set" | CC0 | Block textures |
| OpenGameArt CC0 sounds library | CC0 | SFX |
| Freesound | Per clip: CC0, CC-BY, CC-BY-NC | Filter to CC0 |
| Quaternius | Quaternius Asset License v1.0 | Models; no standalone redistribution |
| Pixel Perfection (XSSheep) | CC BY-SA 4.0 | Share-alike; avoid mixing |
| Press Start 2P | SIL OFL 1.1 | Pixel font |
| Incompetech (Kevin MacLeod) | Free tier requires credit | Music |
| Poly Pizza | Per model; terms silent | Check each model |
| Blockbench | GPL-3.0 | Stand-in model editor |

## Open questions
- Keep PokeAPI's BSD copyright notice in the repo (cheap and safe).
- Confirm Godot 4 glTF import and the Blockbench export list against current docs.
- Music: credited Incompetech, or CC0-only OpenGameArt?
