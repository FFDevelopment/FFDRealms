extends RefCounted
## Versioned local profiles. Writes use a temporary file, then rotate a backup.
## No objects are deserialized and profile IDs never become arbitrary paths.
const SCHEMA: int = 1
const DIRECTORY: String = "user://profiles"
const MAX_BYTES: int = 1048576

static func profile_path(slot: int) -> String:
	return "%s/slot_%d.json" % [DIRECTORY, clampi(slot, 1, 3)]

static func exists(slot: int) -> bool:
	return FileAccess.file_exists(profile_path(slot)) or FileAccess.file_exists(profile_path(slot) + ".bak")

static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "No save in this slot."}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Cannot read the profile file."}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"ok": false, "error": "Profile exceeds the size limit."}
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "Invalid profile JSON."}
	var envelope: Dictionary = parser.data
	if envelope.get("schema", -1) != SCHEMA:
		return {"ok": false, "error": "Unsupported save version; original file preserved."}
	if not envelope.get("character", null) is Dictionary:
		return {"ok": false, "error": "Missing character data."}
	return {"ok": true, "data": envelope["character"]}

static func load_profile(slot: int) -> Dictionary:
	return load_file(profile_path(slot))

static func profile_summary(slot: int) -> Dictionary:
	var loaded: Dictionary = load_profile(slot)
	if not bool(loaded.get("ok", false)):
		return {"exists": exists(slot), "name": "Saved adventure" if exists(slot) else "Empty", "build": ""}
	var data: Dictionary = loaded.get("data", {})
	var name: String = str(data.get("name", "Adventurer")).replace("\n", " ").replace("\r", " ").strip_edges().substr(0, 16)
	if name.is_empty():
		name = "Adventurer"
	return {"exists": true, "name": name, "build": str(data.get("build", "")), "recovered": bool(loaded.get("recovered", false))}


static func load_file(path: String) -> Dictionary:
	var result: Dictionary = read_file(path)
	if bool(result.get("ok", false)):
		return result
	var backup: Dictionary = read_file(path + ".bak")
	if bool(backup.get("ok", false)):
		backup["recovered"] = true
		return backup
	return result

static func write_profile(slot: int, character: Dictionary) -> Error:
	return write_file(profile_path(slot), character)

static func write_file(path: String, character: Dictionary) -> Error:
	# Explicit path helper allows isolated test files; never accepts a UI filename.
	var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if error != OK:
		return error
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"schema": SCHEMA, "character": character}, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	if not bool(read_file(temporary).get("ok", false)):
		return ERR_FILE_CORRUPT
	var absolute: String = ProjectSettings.globalize_path(path)
	var rotated: bool = false
	if FileAccess.file_exists(path):
		if bool(read_file(path).get("ok", false)):
			if FileAccess.file_exists(path + ".bak"):
				error = DirAccess.remove_absolute(absolute + ".bak")
				if error != OK:
					return error
			error = DirAccess.rename_absolute(absolute, absolute + ".bak")
			rotated = error == OK
		else:
			# Do not overwrite a good backup with a corrupted primary profile.
			var quarantine: String = absolute + ".corrupt_%d" % Time.get_unix_time_from_system()
			error = DirAccess.rename_absolute(absolute, quarantine)
		if error != OK:
			return error
	error = DirAccess.rename_absolute(absolute + ".tmp", absolute)
	if error != OK and rotated:
		DirAccess.rename_absolute(absolute + ".bak", absolute)
	return error
