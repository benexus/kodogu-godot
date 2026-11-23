extends SceneTree

## Checks that the add-on's scripts raise none of the warnings Godot shows by default, as the
## Godot Asset Store asks. Godot hides warnings for anything under res://addons/ and reads its
## warning settings only at startup, so this builds a small probe project in the folder given,
## with add-on warnings shown and turned into errors, copies the add-on into it, and parses each
## script there in a new Godot process. From addons/godot:
##
##   godot --headless --path . --script res://test/test_warnings.gd -- <empty folder>

const ADDON := "res://addons/kodogu"

var failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not DirAccess.dir_exists_absolute(args[0]) or not DirAccess.get_files_at(args[0]).is_empty() \
			or not DirAccess.get_directories_at(args[0]).is_empty():
		printerr("Pass one empty folder after --.")
		quit(2)
		return
	var probe: String = args[0]

	# The probe's project.godot: every warning that is on by default becomes an error, and the
	# rule that hides warnings under res://addons/ is dropped.
	var config := ConfigFile.new()
	config.set_value("", "config_version", 5)
	config.set_value("application", "config/name", "Kodogu warnings probe")
	var raised := 0
	for p in ProjectSettings.get_property_list():
		var name: String = p.name
		if not name.begins_with("debug/gdscript/warnings/"):
			continue
		var key := name.trim_prefix("debug/")
		var value = ProjectSettings.get_setting(name)
		if value is Dictionary:
			config.set_value("debug", key, {})
		elif name.ends_with("exclude_addons"):
			config.set_value("debug", key, false)
		elif p.type == TYPE_INT and value == 1:
			config.set_value("debug", key, 2)
			raised += 1
	if raised == 0:
		printerr("No warning settings found; this Godot is not supported by the test.")
		quit(2)
		return
	config.save(probe.path_join("project.godot"))

	var target := probe.path_join("addons/kodogu")
	DirAccess.make_dir_recursive_absolute(target)
	var scripts := PackedStringArray()
	for file in DirAccess.get_files_at(ADDON):
		if file.ends_with(".gd") or file == "plugin.cfg":
			DirAccess.copy_absolute(ProjectSettings.globalize_path(ADDON.path_join(file)), target.path_join(file))
			if file.ends_with(".gd"):
				scripts.append(file)

	for file in scripts:
		var output := []
		OS.execute(OS.get_executable_path(), ["--headless", "--path", probe, "--check-only",
			"--script", "res://addons/kodogu/" + file], output, true)
		var errors := PackedStringArray()
		for line in "\n".join(output).split("\n"):
			if line.contains("Parse Error") or line.contains("Compile Error") and not line.contains("depended"):
				errors.append(line.strip_edges())
		print(("ok    " if errors.is_empty() else "FAIL  ") + file)
		for e in errors:
			print("      " + e)
		if not errors.is_empty():
			failures += 1
	print("No warnings (%d kinds checked)." % raised if failures == 0 else "%d scripts have warnings." % failures)
	quit(1 if failures > 0 else 0)
