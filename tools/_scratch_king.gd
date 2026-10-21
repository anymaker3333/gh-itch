extends SceneTree
var _frame: int = 0
func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	var core: Variant = (load("res://tools/_scratch_king_core.gd") as GDScript).new()
	core.run()
	quit(0)
	return true
