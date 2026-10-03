extends Node

const BOOT_LOG_NAME := "ffdrealms-boot.log"
const GAME_SCENE := "res://scenes/main.tscn"

func _ready() -> void:
	_write_boot("BOOT: bootstrap scene started")
	_write_boot("BOOT: executable=" + OS.get_executable_path())
	_write_boot("BOOT: project=" + str(ProjectSettings.get_setting("application/config/name", "unknown")))
	_write_boot("BOOT: engine=" + Engine.get_version_info().get("string", "unknown"))
	var packed: PackedScene = load(GAME_SCENE)
	if packed == null:
		_write_boot("FAIL: could not load " + GAME_SCENE)
		get_tree().quit(21)
		return
	_write_boot("BOOT: main scene resource loaded")
	var game: Node = packed.instantiate()
	if game == null:
		_write_boot("FAIL: could not instantiate main scene")
		get_tree().quit(22)
		return
	add_child(game)
	_write_boot("BOOT: main scene instantiated")

func _write_boot(line: String) -> void:
	print(line)
	var base := OS.get_executable_path().get_base_dir()
	var path := base.path_join(BOOT_LOG_NAME)
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(line)
	file.close()
