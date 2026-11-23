extends SceneTree

## Checks the installer's refusals on disk, without the network: links (Windows junctions and
## symbolic links, or symlinks elsewhere) on the way to res://assets/<slug>/ or in place of
## CREDITS.md, and a CREDITS.md that is not clean UTF-8. From addons/godot:
##
##   godot --headless --path . --script res://test/test_install.gd -- <empty folder>
##
## The folder holds a stand-in project and an "outside" folder the links point to; nothing may
## ever be written outside. Symbolic links need Developer Mode or admin rights on Windows; the
## checks that need one are skipped, and said to be, when it cannot be made.

const Api := preload("res://addons/kodogu/kodogu_api.gd")
const Install := preload("res://addons/kodogu/kodogu_install.gd")

var failures := 0
var skipped := 0
var api: Api


func check(label: String, ok: bool) -> void:
	print(("ok    " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


## Makes a link; kind is "junction", "dir" or "file". Returns false when the system refuses.
func link(at: String, target: String, kind: String) -> bool:
	if OS.get_name() == "Windows":
		var flag: String = {"junction": "/J", "dir": "/D", "file": ""}[kind]
		var args := ["/c", "mklink"]
		if flag != "":
			args.append(flag)
		args.append_array([at.replace("/", "\\"), target.replace("/", "\\")])
		OS.execute("cmd.exe", args, [], true)
	else:
		if kind == "junction":
			kind = "dir"
		OS.execute("ln", ["-s", target, at])
	return is_link_here(at)


## The test's own link check, so a broken Install.is_link cannot hide a link from the test.
func is_link_here(path: String) -> bool:
	var dir := DirAccess.open(path.get_base_dir())
	return dir != null and dir.is_link(path.get_file())


## Writes a file and closes it, so the bytes are on disk before the next check.
func write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func asset(slug: String) -> Dictionary:
	return {
		"id": 1, "slug": slug, "title": "T", "author": {"handle": "abc", "displayName": null},
		"files": [{"id": 1, "name": "a.glb", "format": "glb", "sizeBytes": 3, "sha256": "0".repeat(64), "hasScripts": false}],
	}


func outside_untouched(outside: String) -> bool:
	return DirAccess.get_files_at(outside).is_empty() and DirAccess.get_directories_at(outside).is_empty()


func fresh(base: String, name: String) -> Array:
	var project := base.path_join(name + "-project")
	var outside := base.path_join(name + "-outside")
	DirAccess.make_dir_recursive_absolute(project)
	DirAccess.make_dir_recursive_absolute(outside)
	return [project, outside]


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not DirAccess.dir_exists_absolute(args[0]) or not DirAccess.get_files_at(args[0]).is_empty() \
			or not DirAccess.get_directories_at(args[0]).is_empty():
		printerr("Pass one empty folder after --.")
		quit(2)
		return
	var base: String = args[0]
	api = Api.new()
	get_root().add_child(api)

	# A junction (or directory symlink) at assets/ or at assets/<slug>/.
	for kind in ["junction", "dir"]:
		for where in ["assets", "assets/crate"]:
			var pair := fresh(base, "%s-%s" % [kind, where.replace("/", "-")])
			var project: String = pair[0]
			var outside: String = pair[1]
			if where == "assets/crate":
				DirAccess.make_dir_absolute(project.path_join("assets"))
			if not link(project.path_join(where), outside, kind):
				print("skip  %s link at %s (the system refused to make one)" % [kind, where])
				skipped += 1
				continue
			var installer := Install.new(project)
			var p: Dictionary = await installer.plan(api, asset("crate"), [1])
			check("%s at %s: plan refuses" % [kind, where], not p.ok and p.error.contains("link"))
			var made := installer.make_folders(["assets", "crate"])
			check("%s at %s: making folders refuses" % [kind, where], not made.ok)
			check("%s at %s: nothing written outside" % [kind, where], outside_untouched(outside))

	# A link in place of CREDITS.md, to a file and to a folder.
	for kind in ["file", "junction"]:
		var pair := fresh(base, "credits-" + kind)
		var project: String = pair[0]
		var outside: String = pair[1]
		var target := outside if kind == "junction" else outside.path_join("theirs.md")
		if kind == "file":
			write(target, ("theirs\n").to_utf8_buffer())
		if not link(project.path_join("CREDITS.md"), target, kind):
			print("skip  %s link as CREDITS.md (the system refused to make one)" % kind)
			skipped += 1
			continue
		var installer := Install.new(project)
		var p: Dictionary = await installer.plan(api, asset("crate"), [1])
		check("CREDITS.md as a %s link: plan refuses" % kind, not p.ok)
		check("CREDITS.md as a %s link: reading refuses" % kind, not installer.read_credits().ok)
		if kind == "file":
			check("CREDITS.md as a file link: its target is untouched",
				FileAccess.get_file_as_string(target) == "theirs\n")

	# A link at the file's own place is "different", and the rename replaces the link, not its target.
	var pair := fresh(base, "final")
	var project: String = pair[0]
	var outside: String = pair[1]
	DirAccess.make_dir_recursive_absolute(project.path_join("assets/crate"))
	var target := outside.path_join("theirs.glb")
	write(target, ("theirs").to_utf8_buffer())
	var final := project.path_join("assets/crate/a.glb")
	if link(final, target, "file"):
		check("a link at the file's place is different",
			await Install.existing_state(api, final, "0".repeat(64)) == "different")
		var partial := project.path_join("assets/crate/.a.glb.kodogu-partial")
		write(partial, ("ours").to_utf8_buffer())
		check("putting the file in place over the link works", Install.put_in_place(partial, final))
		check("the link's target is untouched", FileAccess.get_file_as_string(target) == "theirs")
		check("the file is now a plain file", not is_link_here(final) and FileAccess.get_file_as_string(final) == "ours")
	else:
		print("skip  file link at the file's place (the system refused to make one)")
		skipped += 1

	# CREDITS.md that is not clean UTF-8 is never rewritten; a UTF-8 BOM is kept.
	pair = fresh(base, "encoding")
	project = pair[0]
	var installer := Install.new(project)
	var credits := project.path_join("CREDITS.md")
	var utf16 := PackedByteArray([0xff, 0xfe]) + "# Credits\n".to_utf16_buffer()
	write(credits, utf16)
	check("UTF-16 CREDITS.md is refused", not installer.read_credits().ok)
	write(credits, PackedByteArray([0x61, 0x00, 0x62]))
	check("CREDITS.md with a NUL is refused", not installer.read_credits().ok)
	write(credits, PackedByteArray([0x61, 0xc3, 0x28]))
	check("CREDITS.md with a broken UTF-8 sequence is refused", not installer.read_credits().ok)
	write(credits, PackedByteArray([0xef, 0xbb, 0xbf]) + "# Credits\n\n- x\n".to_utf8_buffer())
	var with_bom: Dictionary = installer.read_credits()
	check("UTF-8 with a BOM is read", with_bom.ok and with_bom.text.unicode_at(0) == 0xfeff)
	write(credits, ("# Credits\n\n- é ✓\n").to_utf8_buffer())
	var plain: Dictionary = installer.read_credits()
	check("plain UTF-8 is read as is", plain.ok and plain.text == "# Credits\n\n- é ✓\n")

	# Writing the credit line: appended after what is there, a BOM written back, the old text kept
	# when the partial file's place is taken.
	var lic := {"id": "CC-BY-4.0", "url": "https://example.org/by/", "attributionRequired": true}
	var page := "https://example.org/assets/1/crate"
	var bom := PackedByteArray([0xef, 0xbb, 0xbf])
	write(credits, bom + "# Credits\n\n- x\n".to_utf8_buffer())
	var c1: Dictionary = installer._credit(asset("crate"), lic, page)
	var after := FileAccess.get_file_as_bytes(credits)
	check("credit line is added (%s)" % c1.get("message", c1.get("error")), c1.ok)
	check("the BOM and the old lines are kept", after.slice(0, 3) == bom
		and after.slice(3).get_string_from_utf8().begins_with("# Credits\n\n- x\n- \"T\" by @abc, CC-BY-4.0"))
	var c2: Dictionary = installer._credit(asset("crate"), lic, page)
	check("a second credit is not added", c2.ok and FileAccess.get_file_as_bytes(credits) == after)
	var v2 := asset("crate")
	v2.version = {"number": 2}
	var c4: Dictionary = installer._credit(v2, lic, page)
	after = FileAccess.get_file_as_bytes(credits)
	var text := after.slice(3).get_string_from_utf8()
	check("a newer version's credit replaces the line (%s)" % c4.get("message", c4.get("error")),
		c4.ok and c4.message.begins_with("Updated") and text.contains("- \"T\" (version 2) by @abc")
		and text.count("via Kodogu:") == 1 and after.slice(0, 3) == bom)
	DirAccess.make_dir_absolute(project.path_join(".CREDITS.md.kodogu-partial"))
	var c3: Dictionary = installer._credit(asset("other"), lic, "https://example.org/assets/2/other")
	check("a folder in the partial file's place stops the write", not c3.ok)
	check("CREDITS.md is unchanged then", FileAccess.get_file_as_bytes(credits) == after)

	print("%s%s" % ["All checks passed." if failures == 0 else "%d checks failed." % failures,
		"" if skipped == 0 else " %d skipped." % skipped])
	quit(1 if failures > 0 else 0)
