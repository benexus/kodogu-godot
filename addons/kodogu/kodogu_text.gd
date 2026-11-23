@tool
extends RefCounted

## Uploader-written text, made safe the way the CLI does it, so the add-on and `kodogu add` agree
## on file names and on the credit line in CREDITS.md. Ported from
## packages/shared/src/untrusted-text.ts (clean, line, quoted, safeFileName, safeFileNames,
## creditLine), packages/cli/src/credits.ts (markdownText, withCredit) and
## packages/cli/src/install.ts (portableName). test/test_text.gd checks this port against answers
## the TypeScript functions give (test/vectors.json, written by scripts/godot-addon-data.mjs).
##
## One difference: the TypeScript normalises text to NFC first. GDScript cannot, but the site
## stores titles, names and file names in NFC already, so that step changes nothing here.

const Fold := preload("kodogu_fold.gd")

const TRUNCATION_MARK := " […truncated]"
const CAP_TITLE := 120
const CAP_DISPLAY_NAME := 80
const CAP_DESCRIPTION := 1500
const CAP_TAG := 40
const CAP_FILE_STEM := 80
const CREDITS_HEADER := "# Credits\n\n"

## Code points `clean` removes (HIDDEN_RANGES in untrusted-text.ts).
const HIDDEN_RANGES := [
	[0x0000, 0x0008], [0x000b, 0x001f], [0x007f, 0x009f], [0x00ad, 0x00ad], [0x034f, 0x034f],
	[0x061c, 0x061c], [0x115f, 0x1160], [0x17b4, 0x17b5], [0x180b, 0x180f], [0x200b, 0x200b],
	[0x200e, 0x200f], [0x2028, 0x202e], [0x2060, 0x206f], [0x3164, 0x3164], [0xfe00, 0xfe0d],
	[0xfeff, 0xfeff], [0xffa0, 0xffa0], [0xfff9, 0xfffb], [0x1d173, 0x1d17a], [0xe0000, 0xe007f],
	[0xe0100, 0xe01ef],
]

## Code points JavaScript's `\s` and `trim()` treat as white space.
const JS_SPACES := [
	0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0xa0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004,
	0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff,
]

## Quotation marks `quoted` replaces with an apostrophe.
const QUOTES := "\"“”„‟«»"

## Characters markdownText escapes with a backslash.
const MARKDOWN_SPECIAL := "\\`*_[]<>!|~&@"

## Windows device names (WINDOWS_RESERVED in install.ts).
const WINDOWS_RESERVED := "^(?i)(con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³])$"

static var _fold := {}
static var _drop := []
static var _picto := []
static var _reserved: RegEx


static func _is_hidden(cp: int) -> bool:
	for r in HIDDEN_RANGES:
		if cp >= r[0] and cp <= r[1]:
			return true
	return false


static func _is_space(cp: int) -> bool:
	return JS_SPACES.has(cp)


## JavaScript's String.prototype.trim.
static func js_trim(text: String) -> String:
	var start := 0
	var end := text.length()
	while start < end and _is_space(text.unicode_at(start)):
		start += 1
	while end > start and _is_space(text.unicode_at(end - 1)):
		end -= 1
	return text.substr(start, end - start)


## Removes hidden characters and normalises line endings; `single_line` folds all white space.
## Text and emoji presentation selectors (U+FE0E, U+FE0F) stay only right after an emoji.
static func clean(text: String, single_line := false) -> String:
	_load_fold()
	text = text.replace("\r\n", "\n").replace("\r", "\n")
	var out := PackedStringArray()
	var in_space := false
	var prev := -1
	for i in text.length():
		var cp := text.unicode_at(i)
		if _is_hidden(cp):
			continue
		var after := prev
		prev = cp
		if (cp == 0xfe0e or cp == 0xfe0f) and not _in_ranges(after, _picto):
			continue
		if single_line and _is_space(cp):
			if not in_space:
				out.append(" ")
			in_space = true
			continue
		in_space = false
		out.append(String.chr(cp))
	var joined := "".join(out)
	if not single_line:
		while joined.contains("\n\n\n"):
			joined = joined.replace("\n\n\n", "\n\n")
	return js_trim(joined)


## Cleaned and capped to `max_chars` code points, with TRUNCATION_MARK when cut.
static func capped(text: String, max_chars: int, single_line := false) -> String:
	var cleaned := clean(text, single_line)
	if cleaned.length() <= max_chars:
		return cleaned
	var cut := cleaned.substr(0, max_chars)
	var end := cut.length()
	while end > 0 and _is_space(cut.unicode_at(end - 1)):
		end -= 1
	return cut.substr(0, end) + TRUNCATION_MARK


## A single-line value (title, name, tag): cleaned, folded to one line and capped.
static func line(text: String, max_chars: int) -> String:
	return capped(text, max_chars, true)


## Uploader text inside a quoted sentence: quotation marks become apostrophes.
static func quoted(text: String, max_chars: int) -> String:
	var out := line(text, max_chars)
	for q in QUOTES:
		out = out.replace(q, "'")
	return out


## Backslash-escapes Markdown and HTML, and breaks automatic links (credits.ts markdownText).
static func markdown_text(text: String) -> String:
	var out := PackedStringArray()
	for ch in text:
		if MARKDOWN_SPECIAL.contains(ch):
			out.append("\\")
		out.append(ch)
	var escaped := "".join(out).replace("://", ":\\/\\/")
	# (www)\. without regard to case: "www." becomes "www\." keeping the original letters.
	var result := ""
	var from := 0
	while true:
		var at := escaped.findn("www.", from)
		if at == -1:
			break
		result += escaped.substr(from, at + 3 - from) + "\\."
		from = at + 4
	return result + escaped.substr(from)


## `"<title>" by <name> (@handle), <licence id> (<licence url>), via Kodogu: <page url>`, with
## the uploader's parts and the licence id escaped for Markdown (credits.ts creditsEntry).
## The prop's version number: its current version's, 1 when the answer has none (a site from
## before versions).
static func version_number(asset: Dictionary) -> int:
	var v = asset.get("version")
	if v is Dictionary and (v.get("number") is int or v.get("number") is float):
		return maxi(1, int(v.number))
	return 1


## creditLine with markdownText as the escape: ` (version <n>)` follows the title from version 2 on.
static func credits_entry(asset: Dictionary, license_id: String, license_url: String, page_url: String) -> String:
	var author: Dictionary = asset.get("author", {})
	var number := version_number(asset)
	var title := markdown_text(quoted(str(asset.get("title", "")), CAP_TITLE)) 		+ ("\" (version %d)" % number if number > 1 else "\"")
	var handle := "@" + markdown_text(str(author.get("handle", "")))
	var who := handle
	var display = author.get("displayName")
	if display is String and display != "":
		who = "%s (%s)" % [markdown_text(quoted(display, CAP_DISPLAY_NAME)), handle]
	return "\"%s by %s, %s (%s), via Kodogu: %s" % [
		title, who, markdown_text(license_id), license_url, page_url,
	]


## The page URL up to its id: the slug after it may change, the id does not.
static func _id_part(page_url: String) -> String:
	return page_url.substr(0, page_url.rfind("/") + 1)


## Whether CREDITS.md already has a line for the prop with this page URL (any version).
static func credits_prop(existing, page_url: String) -> bool:
	return existing != null and (existing as String).contains("via Kodogu: " + _id_part(page_url))


## CREDITS.md with the entry added, or null when the prop is already credited with exactly this
## line. The prop's generated line that differs (another version, another licence) is replaced,
## keeping its line ending; a line the user changed after the URL is left alone (null).
static func with_credit(existing, entry: String, page_url: String):
	if existing == null:
		return CREDITS_HEADER + "- " + entry + "
"
	var marker := "via Kodogu: " + _id_part(page_url)
	var lines := (existing as String).split("
")
	for i in lines.size():
		var l: String = lines[i]
		if not l.contains(marker):
			continue
		var ending := "" if l.ends_with("") else ""
		var text := l.substr(0, l.length() - ending.length())
		if text == "- " + entry:
			return null
		var after := text.substr(text.rfind(marker) + marker.length())
		var generated := text.begins_with("- ")
		for j in after.length():
			if _is_space(after.unicode_at(j)):
				generated = false
		if not generated:
			return null
		lines[i] = "- " + entry + ending
		return "
".join(lines)
	var separator := "" if existing == "" or (existing as String).ends_with("
") else "
"
	return existing + separator + "- " + entry + "
"


static func _load_fold() -> void:
	if not _fold.is_empty():
		return
	for item in Fold.FOLD.split(",", false):
		var eq := item.find("=")
		_fold[item.substr(0, eq).hex_to_int()] = item.substr(eq + 1).replace("~", " ")
	_drop = _parse_ranges(Fold.DROP)
	_picto = _parse_ranges(Fold.PICTO)


static func _parse_ranges(text: String) -> Array:
	var out := []
	for item in text.split(",", false):
		var dash := item.find("-")
		if dash == -1:
			out.append([item.hex_to_int(), item.hex_to_int()])
		else:
			out.append([item.substr(0, dash).hex_to_int(), item.substr(dash + 1).hex_to_int()])
	return out


## Whether cp is in one of the sorted ranges.
static func _in_ranges(cp: int, ranges: Array) -> bool:
	var lo := 0
	var hi := ranges.size() - 1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if cp < ranges[mid][0]:
			hi = mid - 1
		elif cp > ranges[mid][1]:
			lo = mid + 1
		else:
			return true
	return false


static func _dropped(cp: int) -> bool:
	return _in_ranges(cp, _drop)


static func _usable(cp: int) -> bool:
	return (cp >= 0x30 and cp <= 0x39) or (cp >= 0x41 and cp <= 0x5a) or (cp >= 0x61 and cp <= 0x7a) \
		or cp == 0x5f or cp == 0x2d


static func _is_alnum_ascii(text: String) -> bool:
	for i in text.length():
		var cp := text.unicode_at(i)
		if not ((cp >= 0x30 and cp <= 0x39) or (cp >= 0x41 and cp <= 0x5a) or (cp >= 0x61 and cp <= 0x7a)):
			return false
	return true


## A file name made safe for a path inside a project (untrusted-text.ts safeFileName).
static func safe_file_name(name: String, file_id: int, format: String) -> String:
	_load_fold()
	var cleaned := clean(name, true)
	var last := cleaned
	var slash := maxi(cleaned.rfind("/"), cleaned.rfind("\\"))
	if slash != -1:
		last = cleaned.substr(slash + 1)
	var stem := last
	var extension := format
	var dot := last.rfind(".")
	if dot >= 1:
		var ext := last.substr(dot + 1)
		if ext.length() >= 1 and ext.length() <= 10 and _is_alnum_ascii(ext):
			stem = last.substr(0, dot)
			extension = ext
	extension = extension.to_lower()

	# NFKD with marks removed, then every run of unusable characters becomes "_".
	var folded := PackedStringArray()
	for i in stem.length():
		var cp := stem.unicode_at(i)
		if cp < 0x80:
			folded.append(String.chr(cp) if _usable(cp) else " ")
		elif _fold.has(cp):
			folded.append(_fold[cp])
		elif _dropped(cp):
			pass
		else:
			folded.append(" ")
	var parts := PackedStringArray()
	var in_bad := false
	for ch in "".join(folded):
		if ch == " ":
			if not in_bad:
				parts.append("_")
			in_bad = true
		else:
			parts.append(ch)
			in_bad = false
	var safe := "".join(parts)
	while safe.contains("__"):
		safe = safe.replace("__", "_")
	safe = safe.substr(0, CAP_FILE_STEM)
	# No dots are left by now, so trimming "._-" means trimming "_" and "-".
	while safe.length() > 0 and "._-".contains(safe[0]):
		safe = safe.substr(1)
	while safe.length() > 0 and "._-".contains(safe[safe.length() - 1]):
		safe = safe.substr(0, safe.length() - 1)
	var has_alnum := false
	for i in safe.length():
		var cp := safe.unicode_at(i)
		if _usable(cp) and cp != 0x5f and cp != 0x2d:
			has_alnum = true
			break
	if not has_alnum:
		safe = "file-%d" % file_id
	return "%s.%s" % [safe, extension]


## Safe names for all files of a prop, by file id; names that collide get their id appended
## (untrusted-text.ts safeFileNames), then Windows device names get a leading "_" (portableName).
static func safe_file_names(files: Array) -> Dictionary:
	var names := []
	var counts := {}
	for f in files:
		var n := safe_file_name(str(f.name), int(f.id), str(f.format))
		names.append(n)
		counts[n.to_lower()] = counts.get(n.to_lower(), 0) + 1
	var out := {}
	for i in files.size():
		var n: String = names[i]
		if counts[n.to_lower()] >= 2:
			var dot := n.rfind(".")
			n = "%s-%d%s" % [n.substr(0, dot), int(files[i].id), n.substr(dot)]
		out[int(files[i].id)] = portable_name(n)
	return out


## A file or folder name that works on Windows too (install.ts portableName).
static func portable_name(name: String) -> String:
	if _reserved == null:
		_reserved = RegEx.create_from_string(WINDOWS_RESERVED)
	var dot := name.find(".")
	var stem := name if dot == -1 else name.substr(0, dot)
	return "_" + name if _reserved.search(stem) != null else name
