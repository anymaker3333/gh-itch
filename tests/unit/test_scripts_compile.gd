extends RefCounted
## Every script in the project must compile.
##
## The gameplay and service suites only load the files they exercise, so a broken
## *screen* can survive the whole suite and only blow up when the application is
## actually launched (`Parser Error: ...` while `main.tscn` builds its first
## screen). This suite loads every `.gd` file under `res://scripts`,
## `res://tests` and `res://tools` so that a syntax error is a test failure
## instead of a boot failure.

const ROOTS: Array[String] = [
	"res://scripts",
	"res://tests",
	"res://tools",
]


func suite_name() -> String:
	return "compilation"


func run(h: TestHarness) -> void:
	var files := _collect()
	h.greater(float(files.size()), 40.0, "the project contains a substantial number of scripts")
	var broken: Array[String] = []
	for path: String in files:
		if not _compiles(path):
			broken.append(path)
	for path: String in broken:
		h.check(false, "%s does not compile" % path)
	h.equal(broken.size(), 0, "every script in %s compiles" % ", ".join(ROOTS))


func _collect() -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	for root: String in ROOTS:
		_collect_dir(root, files)
	files.sort()
	return files


func _collect_dir(dir: String, out: PackedStringArray) -> void:
	var directories := DirAccess.get_directories_at(dir)
	directories.sort()
	for name: String in directories:
		_collect_dir("%s/%s" % [dir, name], out)
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for name: String in files:
		if name.ends_with(".gd"):
			out.append("%s/%s" % [dir, name])


## `load()` returns a [GDScript] object even when the source has a parse error -
## such a script simply cannot be instantiated.
func _compiles(path: String) -> bool:
	var resource := load(path)
	if not (resource is GDScript):
		return false
	return (resource as GDScript).can_instantiate()
