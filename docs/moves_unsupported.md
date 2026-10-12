# Moves whose effect is not fully implemented

Source: the move validation in the combat integration test (check k, `moves_logic.warnings`), run over
`mods/minemon/minemon_core/data/moves.json`. All 228 moves pass `validate()`, so each one can be used. The
entries below run but do not do everything their name or data suggests. 87 warnings in total,
grouped by reason. Each line gives the move id and its archetype.

Regenerate: run `bash scripts/check.sh`, then read `moves_report.txt` in the combat test's world directory.

## status move with no implemented effect: does nothing (43)

- baton_pass (aura)
- belly_drum (aura)
- conversion (aura)
- conversion_2 (status_cloud)
- curse (status_cloud)
- destiny_bond (aura)
- encore (status_cloud)
- endure (aura)
- focus_energy (aura)
- haze (status_cloud)
- heal_bell (aura)
- light_screen (aura)
- lock_on (status_cloud)
- mean_look (status_cloud)
- metronome (aura)
- milk_drink (aura)
- mimic (status_cloud)
- mind_reader (status_cloud)
- mirror_move (status_cloud)
- mist (aura)
- moonlight (aura)
- morning_sun (aura)
- pain_split (status_cloud)
- psych_up (status_cloud)
- rain_dance (status_cloud)
- recover (aura)
- reflect (aura)
- rest (aura)
- roar (status_cloud)
- safeguard (aura)
- sandstorm (status_cloud)
- sketch (status_cloud)
- soft_boiled (aura)
- spider_web (status_cloud)
- spikes (status_cloud)
- spite (status_cloud)
- splash (aura)
- substitute (aura)
- sunny_day (status_cloud)
- synthesis (aura)
- teleport (aura)
- transform (status_cloud)
- whirlwind (status_cloud)

## status outside the minimal set: ignored (17)

- bind (melee_arc), status `trap`
- clamp (projectile), status `trap`
- confuse_ray (status_cloud), status `confusion`
- confusion (projectile), status `confusion`
- detect (aura), status `protect`
- disable (status_cloud), status `disable`
- dizzy_punch (melee_arc), status `confusion`
- fire_spin (projectile), status `trap`
- foresight (status_cloud), status `no-type-immunity`
- leech_seed (status_cloud), status `leech-seed`
- perish_song (status_cloud), status `perish-song`
- protect (aura), status `protect`
- psybeam (projectile), status `confusion`
- supersonic (status_cloud), status `confusion`
- swagger (status_cloud), status `confusion`
- sweet_kiss (status_cloud), status `confusion`
- wrap (melee_arc), status `trap`

## no power: deals no damage (16)

- bide (melee_arc)
- counter (melee_arc)
- dragon_rage (projectile)
- fissure (beam)
- flail (melee_arc)
- guillotine (melee_arc)
- horn_drill (melee_arc)
- magnitude (area_burst)
- mirror_coat (projectile)
- night_shade (beam)
- present (beam)
- psywave (projectile)
- reversal (melee_arc)
- seismic_toss (melee_arc)
- sonic_boom (beam)
- super_fang (melee_arc)

## flinch is not implemented: ignored (11)

- bite (projectile)
- bone_club (beam)
- headbutt (melee_arc)
- hyper_fang (melee_arc)
- rock_slide (area_burst)
- rolling_kick (melee_arc)
- sky_attack (beam)
- snore (beam)
- stomp (melee_arc)
- twister (area_burst)
- waterfall (projectile)
