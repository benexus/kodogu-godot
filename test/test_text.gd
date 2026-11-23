extends SceneTree

## Checks the add-on's GDScript port of the CLI's naming and credit rules against answers the
## TypeScript functions gave (vectors.json, written by scripts/godot-addon-data.mjs). Run from
## addons/godot: godot --headless --path . --script res://test/test_text.gd

const Text := preload("res://addons/kodogu/kodogu_text.gd")

var failures := 0
var checks := 0


func expect(label: String, got, want) -> void:
	checks += 1
	if got != want:
		failures += 1
		printerr("FAIL %s\n  got:  %s\n  want: %s" % [label, var_to_str(got), var_to_str(want)])


func _init() -> void:
	var text := FileAccess.get_file_as_string("res://test/vectors.json")
	var v: Dictionary = JSON.parse_string(text)

	for case in v.names:
		var files: Array = case.files
		for i in files.size():
			var f: Dictionary = files[i]
			expect("safe_file_name %s" % f.name,
				Text.safe_file_name(f.name, int(f.id), f.format), case.single[i])
		var names := Text.safe_file_names(files)
		for i in files.size():
			expect("safe_file_names %s" % files[i].name, names[int(files[i].id)], case.names[i])

	for case in v.credits:
		expect("credits_entry %s" % case.asset.title,
			Text.credits_entry(case.asset, case.license.id, case.license.url, case.page), case.entry)

	for case in v.withCredits:
		expect("with_credit %s" % var_to_str(case.existing),
			Text.with_credit(case.existing, case.entry, case.page), case.result)

	for case in v.lines:
		expect("line %s" % case.text, Text.line(case.text, int(case.max)), case.line)
		expect("quoted %s" % case.text, Text.quoted(case.text, int(case.max)), case.quoted)

	for case in v.markdown:
		expect("markdown_text %s" % case.text, Text.markdown_text(case.text), case.escaped)

	print("%d of %d checks passed." % [checks - failures, checks])
	quit(1 if failures > 0 else 0)
