@tool
extends VBoxContainer

## The Kodogu screen: search and filters on top, a grid of props on the left, the chosen prop on
## the right with its licence, formats, files and the "contains scripts" flag, and Install.
## Everything an uploader wrote (titles, names, descriptions, tags, file names) is shown as plain
## text in Labels, never as BBCode, and cleaned and capped first.

const Api := preload("kodogu_api.gd")
const Install := preload("kodogu_install.gd")
const Text := preload("kodogu_text.gd")

const ENGINES := [["Any engine", ""], ["Godot", "godot"], ["Blender", "blender"], ["Other", "other"]]
const SORTS := [["Best match / newest", ""], ["Newest", "new"], ["Hot", "hot"], ["Top voted", "top"], ["Most downloaded", "downloads"]]
const CARD_IMAGE := 160

## Returns the site to use (set by plugin.gd, read again on every search).
var site_value: Callable

var _api: Api
var _query: LineEdit
var _format: OptionButton
var _engine: OptionButton
var _sort: OptionButton
var _grid: HFlowContainer
var _status: Label
var _more: Button
var _detail: VBoxContainer
var _cursor = null
var _last_query := {}
var _search_serial := 0
var _detail_serial := 0
var _asset: Dictionary = {}
var _file_boxes := {}
var _install_button: Button
var _log: Label
var _busy := false

signal _dialog_done(ok: bool)


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_api = Api.new()
	add_child(_api)
	_build()
	_show_empty_detail()


func _build() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	_query = LineEdit.new()
	_query.placeholder_text = "Search props, or paste a prop's page URL or id"
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.clear_button_enabled = true
	_query.text_submitted.connect(func(_t): _search())
	bar.add_child(_query)

	_format = OptionButton.new()
	_format.add_item("Any format")
	_format.set_item_metadata(0, "")
	for f in Api.FILE_FORMATS:
		_format.add_item(f.to_upper())
		_format.set_item_metadata(_format.item_count - 1, f)
	bar.add_child(_format)
	_engine = _options(ENGINES)
	bar.add_child(_engine)
	_sort = _options(SORTS)
	bar.add_child(_sort)
	for o in [_format, _engine, _sort]:
		o.item_selected.connect(func(_i): _search())

	var go := Button.new()
	go.text = "Search"
	go.pressed.connect(_search)
	bar.add_child(go)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	split.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	var foot := HBoxContainer.new()
	left.add_child(foot)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(_status)
	_more = Button.new()
	_more.text = "Load more"
	_more.visible = false
	_more.pressed.connect(_load_more)
	foot.add_child(_more)

	var right := ScrollContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size.x = 380
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	right.add_child(_detail)


func _options(items: Array) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(item[0])
		o.set_item_metadata(o.item_count - 1, item[1])
	return o


func _site_ok() -> bool:
	var origin := Api.site_origin(site_value.call() if site_value.is_valid() else "")
	if origin == "":
		_status.text = "The Kodogu site setting is not a usable https address (Editor Settings > Kodogu > Site)."
		return false
	_api.site = origin
	return true


# --- Search ---------------------------------------------------------------------------------

func _search() -> void:
	if not _site_ok():
		return
	var text := _query.text.strip_edges()
	var ref := _parse_ref(text)
	if ref.has("error"):
		_status.text = ref.error
		return
	if ref.has("id"):
		_open(int(ref.id), ref.get("slug", ""), int(ref.get("version", "0")))
		return
	var q := {
		"q": text,
		"format": _format.get_selected_metadata(),
		"engine": _engine.get_selected_metadata(),
		"sort": _sort.get_selected_metadata(),
	}
	_last_query = q
	_cursor = null
	for c in _grid.get_children():
		c.queue_free()
	await _fetch_page()


func _load_more() -> void:
	if _cursor != null:
		await _fetch_page()


func _fetch_page() -> void:
	_search_serial += 1
	var serial := _search_serial
	_status.text = "Searching…"
	_more.visible = false
	var q := _last_query.duplicate()
	if _cursor != null:
		q["cursor"] = _cursor
	var r: Dictionary = await _api.search(q)
	if serial != _search_serial:
		return
	if not r.ok:
		_status.text = r.error
		# The same page can be asked for again.
		_more.visible = _cursor != null
		return
	var body: Dictionary = r.data
	for item in body.items:
		_grid.add_child(_card(item))
	_cursor = body.nextCursor
	_more.visible = _cursor != null
	var shown := _grid.get_child_count()
	_status.text = "No props match." if int(body.total) == 0 else "%d of %d props" % [shown, int(body.total)]


## A page URL on the site, an id, or id/slug opens that prop; anything else is a search
## (ref.ts parseRef, without the slug lookup: a bare slug is searched instead). A version asked
## for (`?version=<n>` on a URL, `@<n>` after an id) comes back as "version"; the add-on installs
## the current version only and says so when another one was asked for.
func _parse_ref(text: String) -> Dictionary:
	var id_re := RegEx.create_from_string("^([1-9][0-9]{0,15})(?:/([a-z0-9]+(?:-[a-z0-9]+)*))?/?\\z")
	var number_re := RegEx.create_from_string("^[1-9][0-9]{0,15}\\z")
	if text.to_lower().begins_with("http://") or text.to_lower().begins_with("https://"):
		# Only the path counts, as with the CLI, and a `version` query parameter.
		var path_end := text.length()
		for ch in "?#":
			var at := text.find(ch)
			if at != -1 and at < path_end:
				path_end = at
		var version := ""
		var hash_at := text.find("#")
		if text.find("?") != -1 and (hash_at == -1 or text.find("?") < hash_at):
			var query := text.substr(text.find("?") + 1, (hash_at if hash_at != -1 else text.length()) - text.find("?") - 1)
			for pair in query.split("&"):
				if pair.begins_with("version="):
					version = pair.substr(8).uri_decode()
					if number_re.search(version) == null:
						return {"error": "Not a version number: %s." % JSON.stringify(Text.line(version, 40))}
					break
		var url_re := RegEx.create_from_string("^(?i)(https?://[^/]+)(?-i)/assets/([^/]+)(?:/([^/]*))?/?\\z")
		var m := url_re.search(text.substr(0, path_end))
		if m == null:
			return {"error": "That URL is not a prop page (/assets/<id>/<slug>)."}
		if Api.site_origin(m.get_string(1)) != _api.site:
			return {"error": "That URL is not on %s. Change Editor Settings > Kodogu > Site to use another Kodogu site." % _api.site}
		text = m.get_string(2) + ("/" + m.get_string(3) if m.get_string(3) != "" else "")
		var idm := id_re.search(text)
		if idm == null:
			return {"error": "That URL is not a prop page (/assets/<id>/<slug>)."}
		var found := {"id": idm.get_string(1), "slug": idm.get_string(2)}
		if version != "":
			found["version"] = version
		return found
	var version_at := text.rfind("@")
	if version_at != -1 and id_re.search(text.substr(0, version_at)) != null:
		var asked := text.substr(version_at + 1)
		if number_re.search(asked) == null:
			return {"error": "Not a version number: %s. Write <id>@<n>." % JSON.stringify(Text.line(asked, 40))}
		var m3 := id_re.search(text.substr(0, version_at))
		return {"id": m3.get_string(1), "slug": m3.get_string(2), "version": asked}
	var m2 := id_re.search(text)
	if m2 != null:
		return {"id": m2.get_string(1), "slug": m2.get_string(2)}
	return {}


func _card(item: Dictionary) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(CARD_IMAGE + 16, CARD_IMAGE + 108)
	button.tooltip_text = Text.line(item.title, Text.CAP_TITLE)
	button.pressed.connect(_open.bind(int(item.id), ""))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	button.add_child(box)
	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(CARD_IMAGE, CARD_IMAGE)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(image)
	box.add_child(_small(Text.line(item.title, Text.CAP_TITLE), true))
	box.add_child(_small("@%s · %s" % [item.author.handle, Text.line(item.license.id, 40)]))
	var formats := ", ".join(item.formats).to_upper()
	var tail := _small(formats + ("  · scripts" if item.hasScripts else ""))
	if item.hasScripts:
		tail.add_theme_color_override("font_color", get_theme_color("warning_color", "Editor"))
	box.add_child(tail)
	_load_image(image, item.thumbnail, 256)
	return button


func _small(text: String, strong := false) -> Label:
	var l := Label.new()
	l.text = text
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = CARD_IMAGE
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not strong:
		l.add_theme_color_override("font_color", get_theme_color("font_disabled_color", "Editor"))
	return l


func _load_image(target: TextureRect, image, width: int) -> void:
	if not image is Dictionary or (image.variants as Array).is_empty():
		return
	var chosen: Dictionary = image.variants[image.variants.size() - 1]
	for v in image.variants:
		if int(v.width) >= width:
			chosen = v
			break
	var texture := await _api.fetch_image(chosen.url)
	if is_instance_valid(target) and texture != null:
		target.texture = texture


# --- The chosen prop ------------------------------------------------------------------------

func _clear_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	_file_boxes.clear()
	_install_button = null
	_log = null


func _show_empty_detail() -> void:
	_clear_detail()
	var l := _wrapped("Search for a prop, then pick one to see its licence, files and whether it contains scripts.")
	_detail.add_child(l)


## Opens prop `id`; `wanted` is a version asked for (0: none), which only changes what is said.
func _open(id: int, slug: String, wanted := 0) -> void:
	if not _site_ok():
		return
	_detail_serial += 1
	var serial := _detail_serial
	_clear_detail()
	_detail.add_child(_wrapped("Loading prop %d…" % id))
	var r: Dictionary = await _api.get_asset(id)
	if serial != _detail_serial:
		return
	_clear_detail()
	if not r.ok:
		_detail.add_child(_wrapped(r.error))
		return
	var asset: Dictionary = r.data
	if slug != "" and asset.slug != slug:
		_detail.add_child(_wrapped("Prop %d is %s, not %s. Check the id, or search with just the id." % [id, asset.slug, slug]))
		return
	_asset = asset
	_show_asset(asset)
	var current := Text.version_number(asset)
	if wanted > 0 and wanted != current:
		var note := _wrapped("You asked for version %d. The add-on installs the current version, %d; download version %d from the prop's page." % [wanted, current, wanted])
		note.add_theme_color_override("font_color", get_theme_color("warning_color", "Editor"))
		_detail.add_child(note)
		_detail.move_child(note, 0)


func _show_asset(a: Dictionary) -> void:
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(0, 280)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail.add_child(preview)
	_load_image(preview, a.thumbnail if a.thumbnail != null else (a.images[0] if not a.images.is_empty() else null), 640)

	var title := _wrapped(Text.line(a.title, Text.CAP_TITLE))
	title.add_theme_font_size_override("font_size", get_theme_font_size("font_size", "Label") + 6)
	_detail.add_child(title)
	var who: String = "@" + a.author.handle
	if a.author.displayName is String and a.author.displayName != "":
		who = "%s (@%s)" % [Text.line(a.author.displayName, Text.CAP_DISPLAY_NAME), a.author.handle]
	_detail.add_child(_wrapped("by " + who))

	var page := LinkButton.new()
	page.text = "Open the prop's page"
	page.tooltip_text = _api.page_url(a)
	page.pressed.connect(func(): OS.shell_open(_api.page_url(a)))
	_detail.add_child(page)

	if a.hasScripts:
		var warn := _wrapped("Contains scripts: GDScript, scenes or add-ons that can run code, or .blend files that can hold Python. The add-on never opens or runs them; read them before you open the prop.")
		warn.add_theme_color_override("font_color", get_theme_color("warning_color", "Editor"))
		_detail.add_child(warn)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	_detail.add_child(grid)
	_row(grid, "Licence", "%s (%s)" % [Text.line(a.license.name, 80), Text.line(a.license.id, 40)])
	var number := Text.version_number(a)
	var versions = a.get("versions")
	var count: int = versions.size() if versions is Array else 1
	if number > 1 or count > 1:
		var label = a.version.get("label") if a.get("version") is Dictionary else null
		_row(grid, "Version", "%d%s%s" % [number,
			" (%s)" % Text.line(label, 32) if label is String and Text.line(label, 32) != "" else "",
			", the current one of %d" % count if count > 1 else ""])
	_row(grid, "Type", "%s in %s" % [Text.line(a.type, 20), Text.line(a.category.name, 60)])
	if a.get("engine") is String:
		_row(grid, "Made for", Text.line(a.engine, 20) + (" " + Text.line(a.engineVersion, 20) if a.get("engineVersion") is String else ""))
	_row(grid, "Formats", ", ".join(a.formats).to_upper() if not a.formats.is_empty() else "none (shared by link)")
	if a.get("polyCount") != null:
		_row(grid, "Polygons", str(int(a.polyCount)))
	var traits := PackedStringArray()
	if a.rigged:
		traits.append("rigged")
	if a.animated:
		traits.append("animated")
	if not traits.is_empty():
		_row(grid, "Model", ", ".join(traits))
	var tools := PackedStringArray()
	for t in a.ai.tools.slice(0, 8):
		tools.append(Text.line(str(t), 60))
	_row(grid, "AI use", Text.line(a.ai.use, 20) + (" (%s)" % ", ".join(tools) if not tools.is_empty() else ""))
	if a.get("stats") is Dictionary:
		_row(grid, "Downloads", str(int(a.stats.get("downloads", 0))))
	var tags := PackedStringArray()
	for t in a.tags.slice(0, 20):
		if t is Dictionary:
			tags.append(Text.line(str(t.get("name", "")), Text.CAP_TAG))
	if not tags.is_empty():
		_row(grid, "Tags", ", ".join(tags))

	var description := Text.capped(a.description, Text.CAP_DESCRIPTION)
	if description != "":
		_detail.add_child(_wrapped(description))

	_detail.add_child(HSeparator.new())
	if a.files.is_empty():
		_detail.add_child(_wrapped("This prop has no files to download (it is shared by link only). Open its page for the link."))
		return
	var folder := Text.portable_name(a.slug)
	_detail.add_child(_wrapped("Files (installed to res://assets/%s/):" % folder))
	var names := Text.safe_file_names(a.files)
	for f in a.files:
		var box := CheckBox.new()
		box.button_pressed = true
		box.text = "%s  ·  %s, %s%s" % [names[int(f.id)], f.format.to_upper(),
			String.humanize_size(int(f.sizeBytes)), "  ·  contains scripts" if f.hasScripts else ""]
		box.tooltip_text = "sha256 %s" % f.sha256
		if f.hasScripts:
			box.add_theme_color_override("font_color", get_theme_color("warning_color", "Editor"))
		_file_boxes[int(f.id)] = box
		_detail.add_child(box)
	_install_button = Button.new()
	_install_button.text = "Install into this project"
	_install_button.pressed.connect(_install)
	_detail.add_child(_install_button)
	_log = _wrapped("")
	_detail.add_child(_log)


func _row(grid: GridContainer, label: String, value: String) -> void:
	var k := Label.new()
	k.text = label
	k.add_theme_color_override("font_color", get_theme_color("font_disabled_color", "Editor"))
	grid.add_child(k)
	var v := _wrapped(value)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(v)


func _wrapped(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	return l


# --- Installing -----------------------------------------------------------------------------

## The log of the prop being installed; it goes away when another prop is opened meanwhile, and
## the lines then only reach the Output panel.
var _install_log: Label


func _say(line: String) -> void:
	if is_instance_valid(_install_log):
		_install_log.text += ("" if _install_log.text == "" else "\n") + line
	print("Kodogu: ", line)


func _install() -> void:
	if _asset.is_empty():
		return
	if _busy:
		if is_instance_valid(_log):
			_log.text = "Another install is still running; wait for it to finish (see the Output panel)."
		return
	_busy = true
	var button := _install_button
	if is_instance_valid(button):
		button.disabled = true
	_install_log = _log
	if is_instance_valid(_install_log):
		_install_log.text = ""
	await _install_steps(_asset)
	_busy = false
	if is_instance_valid(button):
		button.disabled = false


func _install_steps(asset: Dictionary) -> void:
	var chosen := []
	for id in _file_boxes:
		if _file_boxes[id].button_pressed:
			chosen.append(id)
	var installer := Install.new(ProjectSettings.globalize_path("res://"))
	var p: Dictionary = await installer.plan(_api, asset, chosen)
	if not p.ok:
		_say(p.error)
		return
	if not p.scripted.is_empty():
		var ok := await _ask("This prop contains scripts",
			"%s %s scripts (GDScript, add-ons or Python in .blend files).\n\nThe add-on only downloads the files: it does not open, extract or run them. But Godot imports new files as soon as they land, and opening a scene with a tool script, or importing a .blend with the Blender importer turned on, can run its code. Look at the prop first: %s\n\nInstall anyway, and read the scripts before you open or run anything?" % [
				", ".join(p.scripted), "contains" if p.scripted.size() == 1 else "contain", _api.page_url(asset)],
			"Install anyway")
		if not ok:
			_say("Not installed.")
			return
	if not p.different.is_empty():
		var ok := await _ask("Replace files?",
			"%s %s already in res://assets/%s/ with other content. Replace %s?" % [
				", ".join(p.different), "is" if p.different.size() == 1 else "are", p.folder,
				"it" if p.different.size() == 1 else "them"],
			"Replace")
		if not ok:
			_say("Not installed: nothing was changed.")
			return

	# Look again when a question was open: something may have changed meanwhile.
	var again := p
	if not p.scripted.is_empty() or not p.different.is_empty():
		again = await installer.plan(_api, asset, chosen)
		if not again.ok:
			_say(again.error)
			return
		for file_name in again.different:
			if not p.different.has(file_name):
				_say("res://assets/%s/%s changed while the question was open; nothing was installed. Press Install again." % [again.folder, file_name])
				return

	var license: Dictionary = await _api.get_license(asset.license.id)
	var r: Dictionary
	if not license.ok:
		r = license
	else:
		# Before the first file lands: the editor may start importing on its own (it looks for
		# new files whenever its window gets the focus back).
		_hold_import_threads()
		r = await installer.run(_api, asset, license.data, again, _say)
		if int(r.get("installed", 0)) > 0:
			EditorInterface.get_resource_filesystem().scan()
		# Not awaited: the Install button comes back while the editor imports.
		_release_import_threads()
	if not r.ok:
		_say(r.error)


# --- Importing on one thread ----------------------------------------------------------------

## Godot 4.7.2 crashes ("Task 'reimport' already exists", then a segmentation fault) when a
## model with embedded textures is imported into an open project while imports run on several
## threads. A model without textures is fine, and so is the same import on one thread. So from
## just before a prop's files land until the editor has imported them, the project setting
## Editor > Import > Use Multiple Threads is off. Only in memory: this does not save
## project.godot, and the setting gets its own value back afterwards.
const IMPORT_THREADS := "editor/import/use_multiple_threads"
## How long the editor must have imported nothing before the setting goes back. The textures a
## model brings are imported a second time a moment after the model itself.
const IMPORT_QUIET_MSEC := 2000

## Installs that still hold the setting off.
var _import_holds := 0
## The setting's own value while it is held off.
var _import_threads_before: Variant = null
## When the editor last scanned or imported (Time.get_ticks_msec).
var _import_seen_msec := 0


func _hold_import_threads() -> void:
	if _import_holds == 0:
		_import_threads_before = ProjectSettings.get_setting(IMPORT_THREADS, true)
		ProjectSettings.set_setting(IMPORT_THREADS, false)
		var fs := EditorInterface.get_resource_filesystem()
		if not fs.resources_reimported.is_connected(_on_resources_reimported):
			fs.resources_reimported.connect(_on_resources_reimported)
	_import_holds += 1


func _on_resources_reimported(_resources: PackedStringArray) -> void:
	_import_seen_msec = Time.get_ticks_msec()


## Gives up one hold once the editor has been quiet for a while, and puts the setting back with
## the last one.
func _release_import_threads() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	_import_seen_msec = Time.get_ticks_msec()
	while is_inside_tree() and (fs.is_scanning() or Time.get_ticks_msec() - _import_seen_msec < IMPORT_QUIET_MSEC):
		if fs.is_scanning():
			_import_seen_msec = Time.get_ticks_msec()
		await get_tree().process_frame
	if _import_holds > 0:
		_import_holds -= 1
		if _import_holds == 0:
			_restore_import_threads()


func _restore_import_threads() -> void:
	ProjectSettings.set_setting(IMPORT_THREADS, _import_threads_before)
	var fs := EditorInterface.get_resource_filesystem()
	if fs.resources_reimported.is_connected(_on_resources_reimported):
		fs.resources_reimported.disconnect(_on_resources_reimported)


## The add-on is being switched off or the editor is closing: never leave the setting changed.
func _exit_tree() -> void:
	if _import_holds > 0:
		_import_holds = 0
		_restore_import_threads()


func _ask(title: String, text: String, ok_text: String) -> bool:
	var d := ConfirmationDialog.new()
	d.title = title
	d.dialog_text = text
	d.dialog_autowrap = true
	d.ok_button_text = ok_text
	d.min_size = Vector2i(560, 0)
	d.confirmed.connect(func(): _dialog_done.emit(true))
	d.canceled.connect(func(): _dialog_done.emit(false))
	add_child(d)
	d.popup_centered()
	var ok: bool = await _dialog_done
	d.queue_free()
	return ok
