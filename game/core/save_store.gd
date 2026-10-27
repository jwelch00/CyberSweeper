class_name SaveStore
extends RefCounted
## Reads and writes the save files (settings.json, profile.json) in the
## user data folder: %APPDATA%\CyberSweeper on Windows, ~/Library/Application
## Support/CyberSweeper on macOS, ~/.local/share/CyberSweeper on Linux.
## Writes go to a .tmp file first and then replace the real one, so a crash
## mid-save never leaves half a file. A file that won't parse is kept as
## .bad and the game starts fresh. Nothing here touches the network.

const SETTINGS := "settings.json"
const PROFILE := "profile.json"

## Tests point this at a scratch folder so they never touch a real save.
static var dir := "user://"


static func path(name: String) -> String:
	return dir.path_join(name)


static func load_json(name: String) -> Dictionary:
	var p := path(name)
	if not FileAccess.file_exists(p) and FileAccess.file_exists(p + ".tmp"):
		p += ".tmp"   # the replace was interrupted after the old file went
	if not FileAccess.file_exists(p):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(p)) == OK and json.data is Dictionary:
		return json.data
	push_warning("save file %s is unreadable; kept as %s.bad, starting fresh" % [p, name])
	DirAccess.rename_absolute(p, path(name + ".bad"))
	return {}


static func save_json(name: String, d: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var tmp := path(name + ".tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("can't write %s" % tmp)
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	if FileAccess.file_exists(path(name)):
		DirAccess.remove_absolute(path(name))
	return DirAccess.rename_absolute(tmp, path(name)) == OK


static func load_profile() -> Profile:
	return Profile.from_dict(load_json(PROFILE))


static func save_profile(p: Profile) -> bool:
	return save_json(PROFILE, p.to_dict())
