extends SceneTree

## End-to-end check of the add-on's API client and installer against a live Kodogu site. It needs
## the network, counts as a download of each prop, and writes into the folder it is given, so it
## is not part of the normal test run. From addons/godot:
##
##   godot --headless --path . --script res://test/test_live.gd -- <empty folder> <prop id>...
##
## The folder stands in for a game project: the props go to <folder>/assets/<slug>/ and the credit
## lines to <folder>/CREDITS.md, so the result can be compared with `kodogu add` run on another
## folder. The site is the one in plugin.cfg unless KODOGU_SITE is set.

const Api := preload("res://addons/kodogu/kodogu_api.gd")
const Install := preload("res://addons/kodogu/kodogu_install.gd")

var failures := 0


func check(label: String, ok: bool) -> void:
	print(("ok    " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("Pass a folder and one or more prop ids after --.")
		quit(2)
		return
	var folder: String = args[0]
	var ids := args.slice(1)
	var cfg := ConfigFile.new()
	cfg.load("res://addons/kodogu/plugin.cfg")
	var site := OS.get_environment("KODOGU_SITE")
	if site == "":
		site = cfg.get_value("kodogu", "site")
	var api := Api.new()
	api.site = Api.site_origin(site)
	get_root().add_child(api)
	check("site %s is usable" % site, api.site != "")

	var found: Dictionary = await api.search({"q": "", "format": "glb", "sort": "new"})
	check("search answers", found.ok)
	if found.ok:
		check("search finds GLB props", found.data.items.size() > 0)
		for item in found.data.items:
			check("format filter holds for %d" % int(item.id), item.formats.has("glb"))
		var first: Dictionary = found.data.items[0]
		if first.thumbnail != null:
			var tex: Texture2D = await api.fetch_image(first.thumbnail.variants[0].url)
			check("thumbnail of %d loads as a texture" % int(first.id), tex != null and tex.get_width() > 0)
	var missing: Dictionary = await api.get_asset(999999999)
	check("a missing prop gives a clear error", not missing.ok and missing.error.begins_with("No prop"))

	var installer := Install.new(folder)
	for id in ids:
		var r: Dictionary = await api.get_asset(int(id))
		check("prop %s loads" % id, r.ok)
		if not r.ok:
			print("      ", r.error)
			continue
		var asset: Dictionary = r.data
		var lic: Dictionary = await api.get_license(asset.license.id)
		check("licence %s is listed" % asset.license.id, lic.ok)
		var chosen := []
		for f in asset.files:
			chosen.append(int(f.id))
		var p: Dictionary = await installer.plan(api, asset, chosen)
		check("plan for %s" % asset.slug, p.ok)
		var done: Dictionary = await installer.run(api, asset, lic.data, p, func(l): print("      ", l))
		check("install of %s" % asset.slug, done.ok)
		for w in p.work:
			check("%s is in place with its sha256" % w.name,
				await Install.existing_state(api, w.final, w.file.sha256) == "same")
			check("no partial file is left for %s" % w.name,
				not FileAccess.file_exists(w.final.get_base_dir().path_join(".%s.kodogu-partial" % w.name)))

		# Again: everything is already there and credited.
		var again: Dictionary = await installer.plan(api, asset, chosen)
		check("second plan finds the files already there", again.ok and again.work.is_empty())
		var lines := []
		await installer.run(api, asset, lic.data, again, func(l): lines.append(l))
		check("second install does not credit twice", lines.has("CREDITS.md already credits this prop."))

		# A file whose listed checksum or size is wrong is refused and not kept.
		var f0: Dictionary = asset.files[0]
		var tmp := folder.path_join("tampered.bin")
		var bad := f0.duplicate()
		bad.sha256 = "0".repeat(64)
		var t1: Dictionary = await api.download(int(asset.id), bad, tmp)
		check("wrong sha256 is refused", not t1.ok and t1.error.contains("sha256"))
		check("refused download is not kept", not FileAccess.file_exists(tmp))
		bad = f0.duplicate()
		bad.sizeBytes = int(f0.sizeBytes) - 1
		var t2: Dictionary = await api.download(int(asset.id), bad, tmp)
		check("a file larger than listed is refused (%s)" % t2.get("error", ""), not t2.ok)
		check("oversized download is not kept", not FileAccess.file_exists(tmp))

	print("%s" % ("All checks passed." if failures == 0 else "%d checks failed." % failures))
	quit(1 if failures > 0 else 0)
