# S-05 Visual assets (block textures, sky, ambient audio)

## Findings
- **Downloads blocked, nothing downloaded.** The shell egress policy returns 403 for kenney.nl, opengameart.org, content.luanti.org, freesound.org, pixelperfection.org, cdn.jsdelivr.net, cdnjs, unpkg and github.com repos (`gh`: repo access not enabled for this session). No archives were fetched; no contact sheets or previews were made (no real textures to draw). Licence and coverage below come from page text read with WebFetch, not from the archives, so coverage is unverified.
- **Best 16px CC0 candidate:** "16x16 block texture set" (ARoachIFoundOnMyPillow, OpenGameArt). Licence CC0, 16x16, blocks.zip 98.5 KB, tags stone, dirt, sand, logs, plant, flower, cactus. Grass, water, leaves and snow are not confirmed.
- **Kenney Voxel Pack / Isometric Blocks:** CC0. Voxel Pack has 190 files at a 128 px tile size, so it needs downscaling to 16 px. Isometric Blocks has 130 PNGs of unknown size and may be vector-derived. Neither page lists block names.
- **Excluded:** Luanti default textures and Mineclonia textures (CC BY-SA, ShareAlike, outside the CC0/CC-BY/OFL rule). Pixel Perfection and its derivatives (Mineclonia "pixel imperfection", XTended) are built on Minecraft resource packs, so they fall under the Mojang-derived exclusion.
- **Audio:** "Birds and Wind - Ambient" (Spring, OpenGameArt) is CC0, OGG, 1.9 MB. Loop points and duration are not stated. Freesound pages could not be read (robots-disallowed), so its CC0 filter is unverified.
- **Sky:** no licence checked for OpenGameArt sky sets ("Seamless sky backgrounds", "clouds skybox 1").

## Candidates

| Candidate | Licence (page) | Size | Coverage (page text) | Verdict |
|---|---|---|---|---|
| 16x16 block texture set (OGA) | CC0 | 16x16 | stone, dirt, sand, logs, plant, flower | Preferred base, verify contents |
| 1616 block textures (OGA) | CC0 | 16x16 | tags: grass, dirt, sand, logs | Check contents |
| Kenney Voxel Pack | CC0 | 128 px, 190 files | not listed | Check for flat faces |
| Kenney Isometric Blocks | CC0 | unknown | not listed | Low priority |
| Too Many Stones (OGA) | CC0 (author wording mixed) | unknown | stone variants only | Stone supplement |
| Luanti default / Mineclonia | CC BY-SA | 16x16 | full set | Excluded |
| Pixel Perfection family | CC BY-SA on top of Minecraft packs | 16x16 | armour and tools only | Excluded |

## Recommendation
1. Do not add any pack yet. First ask the owner to allow opengameart.org and kenney.nl through the egress policy, or to place the zips in `packs/` manually. Then re-run this scout to build the contact sheets.
2. Fallback that needs no download: generate our own 16x16 textures in code (noise plus a limited palette), packed into one atlas. Nearest filtering, no per-face texture switching, so the draw cost stays low on the Vega 8. This covers every required block with no licence risk.
3. Sky: a procedural gradient and sun disc in a shader. Cheapest option and needs no asset. Clouds can be procedural noise or dropped.
4. Audio: test Spring's "Birds and Wind - Ambient" as a wind and birds loop. Check its loop and duration after download. Find a CC0 forest-night loop and a water loop on Freesound (CC0 filter) once that site is reachable.
5. Record any imported asset in `ASSETS_LICENSES.md` with source URL, author and licence, as CONVENTIONS requires.

## Confidence
- High: the licence text read for the OpenGameArt and Kenney pages (CC0), the Luanti and Mineclonia ShareAlike terms, and the Pixel Perfection Minecraft lineage.
- Medium: block coverage, which comes from tags and descriptions only.
- Low: Freesound CC0 availability, sky set licences, and every pixel size not stated on a page.
- None: the quality of any texture (nothing was viewed).

## Sources
- https://opengameart.org/content/voxel-pack
- https://kenney.nl/assets/voxel-pack
- https://opengameart.org/content/isometric-blocks
- https://opengameart.org/content/16x16-block-texture-set
- https://opengameart.org/content/1616-block-textures
- https://opengameart.org/node/154206 (Too Many Stones)
- https://opengameart.org/content/birds-and-wind-ambient-birds-wind-and-synth
- https://opengameart.org/content/nature-kit
- https://content.luanti.org/packages/Geraos16/pixel_xt_perfection/
- https://codeberg.org/mineclonia/pixel_imperfection
- https://mineclonia.codeberg.page/wiki/guides/texturing.html
- https://bytes.keithhacks.cyou/etc/Mineclonia/commit/9456e90aba7bfbc2a87dcef12c0fa1270bb3fa34
- https://metadata.ftp-master.debian.org/changelogs/main/l/luanti/stable_copyright

## Open questions
- Will the owner allow opengameart.org and kenney.nl through the egress policy, or supply the zips by hand? Without them the contact sheets and previews cannot be made.
- Is an in-house procedural texture atlas acceptable as the default, with imported packs as an upgrade?
- Confirm the ShareAlike exclusion (CC BY-SA is not in the CC0/CC-BY/OFL list in CONVENTIONS).
