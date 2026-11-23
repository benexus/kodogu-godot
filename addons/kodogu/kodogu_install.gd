@tool
extends RefCounted

## Installing a prop into the open project, the way `kodogu add` does it
## (packages/cli/src/cli.ts add, install.ts, credits.ts):
##
## - the files go to res://assets/<slug>/ with the CLI's safe file names;
## - CREDITS.md at the project root gets the CLI's credit line, once per prop;
## - every folder on the way must be a real folder: a link (symlink or junction) stops the install
##   before anything is read or written there (the CLI allows a link that stays inside the
##   project; the add-on refuses all of them, which is simpler and stricter);
## - every file is checked before any download, so a refusal leaves the project as it was;
## - a download goes to a hidden partial file and is renamed into place only once its size and
##   sha256 match, so a failed or rejected download leaves nothing behind;
## - nothing from the prop is opened, imported on purpose, extracted or run. Zip archives stay zipped.

const Text := preload("kodogu_text.gd")
const Api := preload("kodogu_api.gd")

## The project folder (res://) as an absolute path, without a trailing slash.
var root := ""


func _init(project_root: String) -> void:
	root = project_root.rstrip("/")


## What would happen: {"ok", "error"?, "folder", "work": [{file, name, final}], "same": [names],
## "different": [names], "scripted": [names]}. Reads nothing through a link.
func plan(api: Api, asset: Dictionary, chosen_ids: Array) -> Dictionary:
	var files: Array = asset.files
	if files.is_empty():
		return {"ok": false, "error": "This prop has no files to download (it is shared by link only)."}
	if chosen_ids.is_empty():
		return {"ok": false, "error": "Tick at least one file to install."}
	var names := Text.safe_file_names(files)
	var folder := Text.portable_name(asset.slug)
	var seen := {}
	var out := {"ok": true, "folder": folder, "work": [], "same": [], "different": [], "scripted": []}
	for file in files:
		if not chosen_ids.has(int(file.id)):
			continue
		var name: String = names[int(file.id)]
		if seen.has(name.to_lower()):
			return {"ok": false, "error": "Two files of this prop would both be saved as %s; nothing was downloaded. Get them from the prop's page instead." % name}
		seen[name.to_lower()] = true
		if file.hasScripts:
			out.scripted.append(name)
	# The folders first, so nothing below a link is looked at.
	var folders := check_folders(["assets", folder])
	if not folders.ok:
		return folders
	var credits := check_credits()
	if not credits.ok:
		return credits
	for file in files:
		if not chosen_ids.has(int(file.id)):
			continue
		var name: String = names[int(file.id)]
		var final := "%s/assets/%s/%s" % [root, folder, name]
		var state: String = await existing_state(api, final, file.sha256)
		if state == "same":
			out.same.append(name)
		else:
			if state == "different":
				out.different.append(name)
			out.work.append({"file": file, "name": name, "final": final})
	return out


## "absent", "same" (a plain file with this sha256) or "different" (other content, a link or a folder).
static func existing_state(api: Api, path: String, sha256: String) -> String:
	if is_link(path) or DirAccess.dir_exists_absolute(path):
		return "different"
	if not FileAccess.file_exists(path):
		return "absent"
	return "same" if await api.hash_file(path) == sha256 else "different"


## Whether path is a symlink, or on Windows a junction or other reparse point.
static func is_link(path: String) -> bool:
	var dir := DirAccess.open(path.get_base_dir())
	return dir != null and dir.is_link(path.get_file())


## Checks root/<segments> one folder at a time without changing anything: each one that exists
## must be a real folder, not a link or a file.
func check_folders(segments: Array) -> Dictionary:
	var dir := root
	for segment in segments:
		var next: String = dir + "/" + segment
		if is_link(next):
			return {"ok": false, "error": "%s is a link that may lead outside the project; nothing was written." % next}
		if not DirAccess.dir_exists_absolute(next):
			if FileAccess.file_exists(next):
				return {"ok": false, "error": "%s is not a folder; nothing was written." % next}
			return {"ok": true}
		dir = next
	return {"ok": true}


## Checks root/<segments> again and makes the folders that are missing.
## Returns {"ok", "error"?, "dir", "created": [paths]}.
func make_folders(segments: Array) -> Dictionary:
	var dir := root
	var created := []
	for segment in segments:
		var next: String = dir + "/" + segment
		if is_link(next):
			remove_empty_folders(created)
			return {"ok": false, "error": "%s is a link that may lead outside the project; nothing was written." % next}
		if DirAccess.dir_exists_absolute(next):
			pass
		elif FileAccess.file_exists(next):
			remove_empty_folders(created)
			return {"ok": false, "error": "%s is not a folder; nothing was written." % next}
		elif DirAccess.make_dir_absolute(next) == OK:
			created.append(next)
		else:
			remove_empty_folders(created)
			return {"ok": false, "error": "Could not make the folder %s." % next}
		dir = next
	return {"ok": true, "dir": dir, "created": created}


## Removes the folders make_folders made, deepest first, while they are still empty.
static func remove_empty_folders(created: Array) -> void:
	for i in range(created.size() - 1, -1, -1):
		if DirAccess.remove_absolute(created[i]) != OK:
			return


## CREDITS.md must be a plain file or absent.
func check_credits() -> Dictionary:
	var path := root + "/CREDITS.md"
	if is_link(path) or DirAccess.dir_exists_absolute(path):
		return {"ok": false, "error": "%s is not a plain file (it may be a link); nothing was written." % path}
	return {"ok": true}


## CREDITS.md's text (null when there is none), read now. A file that cannot be read, or is not
## clean UTF-8 (UTF-16 from some editors, stray bytes, a NUL), is refused rather than rewritten,
## so the credits already in it are never lost.
func read_credits() -> Dictionary:
	var check := check_credits()
	if not check.ok:
		return check
	var path := root + "/CREDITS.md"
	if not FileAccess.file_exists(path):
		return {"ok": true, "text": null}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "CREDITS.md could not be read; it was left as it is."}
	var bytes := f.get_buffer(f.get_length())
	var read_ok := bytes.size() == f.get_length()
	f.close()
	if not read_ok:
		return {"ok": false, "error": "CREDITS.md could not be read; it was left as it is."}
	# A UTF-8 byte order mark is kept, as the CLI keeps it.
	var bom := bytes.size() >= 3 and bytes[0] == 0xef and bytes[1] == 0xbb and bytes[2] == 0xbf
	var body := bytes.slice(3) if bom else bytes
	var text := body.get_string_from_utf8()
	if text.to_utf8_buffer() != body:
		return {"ok": false, "error": "CREDITS.md is not plain UTF-8 text, so the add-on did not change it. Add the credit line yourself."}
	return {"ok": true, "text": (String.chr(0xfeff) + text) if bom else text}


## Renames the checked partial file to its final name, replacing a file already there. A link
## at that name is removed first (the link itself, never what it points to): Windows will not
## rename over a file link.
static func put_in_place(partial: String, final: String) -> bool:
	if is_link(final) and DirAccess.remove_absolute(final) != OK:
		return false
	return DirAccess.rename_absolute(partial, final) == OK


static func _partial(final: String) -> String:
	return final.get_base_dir().path_join(".%s.kodogu-partial" % final.get_file())


## Downloads the planned files and credits the prop. `say` is called with each line to show.
## Returns {"ok", "error"?, "installed": count}.
func run(api: Api, asset: Dictionary, license: Dictionary, p: Dictionary, say: Callable) -> Dictionary:
	var page := api.page_url(asset)
	var check := check_credits()
	if not check.ok:
		return check
	var made := make_folders(["assets", p.folder])
	if not made.ok:
		return made
	for name in p.same:
		say.call("Already there: res://assets/%s/%s" % [p.folder, name])
	# Always the current version, so the CLI's "an earlier one" wording never applies here.
	var number := Text.version_number(asset)
	say.call("Adding \"%s\"%s by @%s (%s) from %s" % [
		Text.line(asset.title, Text.CAP_TITLE), " version %d" % number if number > 1 else "",
		asset.author.handle, license.id, page])

	var installed: int = p.same.size()
	var failure := ""
	for w in p.work:
		var partial := _partial(w.final)
		if is_link(partial) or DirAccess.dir_exists_absolute(partial):
			failure = "%s is in the way (a link or folder); nothing more was written." % partial
			break
		DirAccess.remove_absolute(partial)
		var r: Dictionary = await api.download(int(asset.id), w.file, partial)
		if not r.ok:
			failure = r.error
			break
		if not put_in_place(partial, w.final):
			DirAccess.remove_absolute(partial)
			failure = "Could not move the download into place at %s." % w.final
			break
		installed += 1
		say.call("Downloaded res://assets/%s/%s (%d bytes, sha256 checked)" % [
			p.folder, w.name, int(w.file.sizeBytes)])
		if w.file.format == "zip":
			say.call("  It is a zip archive: extract it yourself and check what it contains.")

	# Whatever is on disk is credited, even when a later file failed; when nothing is, the folders
	# made for it go again.
	if installed > 0:
		var c := _credit(asset, license, page)
		if not c.ok and failure == "":
			failure = c.error
		elif not c.ok:
			say.call(c.error)
		else:
			say.call(c.message)
	else:
		remove_empty_folders(made.created)
	if failure != "":
		return {"ok": false, "error": failure, "installed": installed}
	if not p.scripted.is_empty():
		say.call("May run code: look inside the files before you open or run the prop.")
	return {"ok": true, "installed": installed}


func _credit(asset: Dictionary, license: Dictionary, page: String) -> Dictionary:
	# Read now, not before the downloads, so an edit made meanwhile is kept.
	var existing := read_credits()
	if not existing.ok:
		return existing
	var entry := Text.credits_entry(asset, license.id, license.url, page)
	var next = Text.with_credit(existing.text, entry, page)
	if next == null:
		return {"ok": true, "message": "CREDITS.md already credits this prop."}
	var path := root + "/CREDITS.md"
	var partial := _partial(path)
	if is_link(partial) or DirAccess.dir_exists_absolute(partial):
		return {"ok": false, "error": "%s is in the way; CREDITS.md was not changed." % partial}
	DirAccess.remove_absolute(partial)
	var bytes := (next as String).to_utf8_buffer()
	var f := FileAccess.open(partial, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Could not write CREDITS.md; it was not changed."}
	f.store_buffer(bytes)
	f.close()
	if FileAccess.get_file_as_bytes(partial) != bytes:
		DirAccess.remove_absolute(partial)
		return {"ok": false, "error": "Could not write CREDITS.md; it was not changed."}
	if DirAccess.rename_absolute(partial, path) != OK:
		DirAccess.remove_absolute(partial)
		return {"ok": false, "error": "Could not write CREDITS.md; it was not changed."}
	# A line for another version (or licence) of the prop was replaced rather than added.
	var done := "Updated" if Text.credits_prop(existing.text, page) else "Added"
	return {"ok": true, "message":
		"%s the credit line in CREDITS.md (%s requires attribution: keep it)." % [done, license.id]
		if license.attributionRequired else "%s the credit line in CREDITS.md." % done}
