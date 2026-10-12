class_name Lives
extends RefCounted
## The player's lives: three deaths lead to a respawn, the fourth is permanent.

const START_LIVES: int = 3

var lives_left: int = START_LIVES


## Returns "respawn" while lives remain (and spends one), otherwise "permadeath".
func on_death() -> String:
	if lives_left > 0:
		lives_left -= 1
		return "respawn"
	return "permadeath"
