class_name CombatantView
extends RefCounted
## What the damage formula needs to know about one combatant at the moment of a hit.

var level: int = 1
var stats: Dictionary = {"hp": 1, "atk": 1, "def": 1, "spa": 1, "spd": 1, "spe": 1}
var types: Array[String] = []
var status: String = ""
var stages: Dictionary = {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0, "acc": 0, "eva": 0}
