class_name DamageResult
extends RefCounted
## Outcome of one hit: damage dealt plus the flags the UI needs.

var amount: int = 0
var crit: bool = false
var effectiveness: float = 1.0
var missed: bool = false
