@tool
extends Node

## The public Kodogu REST API under /api/v1, read anonymously and always with reviewedOnly=true,
## so the add-on sees what the CLI and agents see: only props of accounts that passed their
## first-upload review. Answers are checked field by field before use (the CLI parses them with
## the shared zod schemas in packages/shared/src/api.ts; this is the same check by hand, for the
## fields the add-on uses), and everything an uploader wrote is treated as plain text.
##
## Every call returns a Dictionary: {"ok": true, "data": ...} or {"ok": false, "error": "..."}.

const JSON_TIMEOUT_S := 30.0
const DOWNLOAD_TIMEOUT_S := 30.0 * 60.0
const IMAGE_MAX_BYTES := 4 * 1024 * 1024
## Preview images are at most 1280 wide (IMAGE_VARIANT_WIDTHS); anything far larger is refused
## before it is decoded.
const IMAGE_MAX_SIDE := 4096
const IMAGE_CACHE_MAX := 300
const JSON_MAX_BYTES := 8 * 1024 * 1024
const IMAGE_SLOTS := 4
## Largest whole number a JSON number holds exactly.
const MAX_SAFE_INT := 9007199254740991

const FILE_FORMATS := ["glb", "gltf", "fbx", "obj", "stl", "usdz", "blend", "tscn", "scn", "tres", "zip"]
# \z, not $: in PCRE "$" also matches before a final newline.
const SLUG_PATTERN := "^[a-z0-9]+(?:-[a-z0-9]+)*\\z"
const HANDLE_PATTERN := "^[A-Za-z0-9](?:[A-Za-z0-9_-]*[A-Za-z0-9])?\\z"
const SHA256_PATTERN := "^[0-9a-f]{64}\\z"

## The Kodogu site, e.g. https://example.org, without a trailing slash.
var site := ""

var _slug_re := RegEx.create_from_string(SLUG_PATTERN)
var _handle_re := RegEx.create_from_string(HANDLE_PATTERN)
var _sha_re := RegEx.create_from_string(SHA256_PATTERN)
var _licenses: Array = []
var _licenses_site := ""
var _images := {}
var _image_slots := IMAGE_SLOTS
signal _image_slot_free


static func user_agent() -> String:
	var v := Engine.get_version_info()
	return "KodoguGodotAddon/0.1 (Godot %s.%s)" % [v.major, v.minor]


## The site from a setting: https, or http on this computer (for a local dev server); the origin
## only. Returns "" when the value cannot be used.
static func site_origin(value: String) -> String:
	value = value.strip_edges()
	var re := RegEx.create_from_string("^(?i)(https?)://([a-z0-9.-]+|\\[[0-9a-f:]+\\])(:[0-9]{1,5})?/?\\z")
	var m := re.search(value)
	if m == null:
		return ""
	var scheme := m.get_string(1).to_lower()
	var host := m.get_string(2).to_lower()
	var local := host == "localhost" or host == "127.0.0.1" or host == "[::1]" or host.ends_with(".localhost")
	if scheme == "http" and not local:
		return ""
	return "%s://%s%s" % [scheme, host, m.get_string(3)]


func _url(path: String, query := {}) -> String:
	var url := site + "/api/v1" + path
	var parts := PackedStringArray()
	for key in query:
		parts.append("%s=%s" % [key, str(query[key]).uri_encode()])
	if not parts.is_empty():
		url += "?" + "&".join(parts)
	return url


func page_url(asset: Dictionary) -> String:
	return "%s/assets/%d/%s" % [site, int(asset.id), asset.slug]


func _new_request(timeout: float, limit: int) -> HTTPRequest:
	var req := HTTPRequest.new()
	req.timeout = timeout
	req.max_redirects = 0
	req.body_size_limit = limit
	req.use_threads = true
	add_child(req)
	return req


func _get_json(path: String, query := {}, not_found := "") -> Dictionary:
	var req := _new_request(JSON_TIMEOUT_S, JSON_MAX_BYTES)
	var err := req.request(_url(path, query), ["Accept: application/json", "User-Agent: " + user_agent()])
	if err != OK:
		req.queue_free()
		return _fail("Could not reach %s." % site)
	var r: Array = await req.request_completed
	req.queue_free()
	var result: int = r[0]
	var code: int = r[1]
	if result != HTTPRequest.RESULT_SUCCESS and result != HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
		return _fail("Could not reach %s. Check the connection and the site setting." % site)
	if code == 404 and not_found != "":
		return _fail(not_found)
	if code < 200 or code >= 300:
		return _fail("%s answered %d for %s." % [site, code, path])
	var json := JSON.new()
	if json.parse((r[3] as PackedByteArray).get_string_from_utf8()) != OK:
		return _fail("%s sent an answer this add-on does not understand." % site)
	return {"ok": true, "data": json.data}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _not_understood() -> Dictionary:
	return _fail("%s sent an answer this add-on does not understand." % site)


# --- Checks of the answers ------------------------------------------------------------------

static func _is_int(value, minimum := 0) -> bool:
	if not (value is float or value is int):
		return false
	var f := float(value)
	return is_finite(f) and f == floorf(f) and f >= minimum and f <= MAX_SAFE_INT


## `d` has every key, and each value passes its check (a Callable taking the value).
static func _has(d, checks: Dictionary) -> bool:
	if not d is Dictionary:
		return false
	for key in checks:
		if not d.has(key) or not checks[key].call(d[key]):
			return false
	return true


static func _str(v) -> bool:
	return v is String


static func _str_or_null(v) -> bool:
	return v == null or v is String


static func _bool(v) -> bool:
	return v is bool


static func _array(v) -> bool:
	return v is Array


func _image_ok(image) -> bool:
	if image == null:
		return true
	if not _has(image, {"variants": _array, "alt": _str}):
		return false
	for v in image.variants:
		if not _has(v, {"width": func(x): return _is_int(x, 1), "url": _web_url}):
			return false
	return true


## A plain http(s) address without a login, spaces or quotes; http only when the site itself is
## http (a local dev server).
func _web_url(value) -> bool:
	if not value is String:
		return false
	var lower := (value as String).to_lower()
	if not (lower.begins_with("https://") or (lower.begins_with("http://") and site.begins_with("http://"))):
		return false
	for ch in " \"'<>`\\{}|^":
		if value.contains(ch):
			return false
	for i in value.length():
		var cp: int = value.unicode_at(i)
		if cp < 0x21 or cp > 0x7e:
			return false
	var rest := (value as String).substr((value as String).find("://") + 3)
	var authority := rest.get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)
	return authority != "" and not authority.contains("@")


func _slug_ok(v) -> bool:
	return v is String and v.length() <= 80 and _slug_re.search(v) != null


func _summary_ok(a) -> bool:
	if not _has(a, {
		"id": func(x): return _is_int(x, 1),
		"slug": _slug_ok,
		"title": _str,
		"type": _str,
		"license": func(x): return _has(x, {"id": _str, "name": _str}),
		"category": func(x): return _has(x, {"name": _str}),
		"engine": _str_or_null,
		"engineVersion": _str_or_null,
		"polyCount": func(x): return x == null or _is_int(x, 0),
		"rigged": _bool,
		"animated": _bool,
		"ai": func(x): return _has(x, {"use": _str, "tools": _array}),
		"formats": _array,
		"hasScripts": _bool,
		"author": func(x): return _has(x, {
			"handle": func(h): return h is String and h.length() >= 3 and h.length() <= 40 and _handle_re.search(h) != null,
			"displayName": _str_or_null,
		}),
		"thumbnail": _image_ok,
		"stats": func(x): return _has(x, {"downloads": func(n): return _is_int(n, 0)}),
	}):
		return false
	for f in a.formats:
		if not FILE_FORMATS.has(f):
			return false
	return true


func _detail_ok(a) -> bool:
	if not _summary_ok(a) or not _has(a, {"description": _str, "files": _array, "images": _array, "tags": _array}):
		return false
	for f in a.files:
		if not _has(f, {
			"id": func(x): return _is_int(x, 1),
			"name": _str,
			"format": func(x): return FILE_FORMATS.has(x),
			"sizeBytes": func(x): return _is_int(x, 0),
			"sha256": func(x): return x is String and _sha_re.search(x) != null,
			"hasScripts": _bool,
		}):
			return false
	for image in a.images:
		if image == null or not _image_ok(image):
			return false
	return true


# --- Calls ----------------------------------------------------------------------------------

## GET /assets: one page of props. `query` holds q, format, engine, sort, cursor.
func search(query: Dictionary) -> Dictionary:
	var q := {"reviewedOnly": "true", "limit": "24"}
	for key in query:
		if str(query[key]) != "":
			q[key] = str(query[key])
	var r := await _get_json("/assets", q)
	if not r.ok:
		return r
	if not _has(r.data, {"items": _array, "total": func(x): return _is_int(x, 0), "nextCursor": _str_or_null}):
		return _not_understood()
	for item in r.data.items:
		if not _summary_ok(item):
			return _not_understood()
	return r


## GET /assets/:id: one prop with its files.
func get_asset(id: int) -> Dictionary:
	var r := await _get_json("/assets/%d" % id, {"reviewedOnly": "true"},
		"No prop %d is available. It may not exist, not be published yet, or come from an account that has not passed review." % id)
	if not r.ok:
		return r
	if not r.data is Dictionary or not _detail_ok(r.data.get("asset")):
		return _not_understood()
	return {"ok": true, "data": r.data.asset}


## The licence from the site's licence table, made safe for CREDITS.md as the CLI does
## (api.ts getLicense): the id cut to one short line, a plain http(s) URL with brackets encoded.
## The CLI writes the URL as `new URL(url).href`; here the scheme and host are lower-cased and a
## bare host gets its "/", and a URL that would need more than that (spaces, quotes, non-ASCII)
## is refused instead of rewritten. A default port (:443) and dot segments (/a/../b) are not
## normalised as `href` would. The site's licence URLs come out the same either way.
func get_license(id: String) -> Dictionary:
	const Text := preload("kodogu_text.gd")
	if _licenses_site != site:
		_licenses = []
	if _licenses.is_empty():
		var r := await _get_json("/licenses")
		if not r.ok:
			return r
		if not _has(r.data, {"items": _array}):
			return _not_understood()
		_licenses = r.data.items
		_licenses_site = site
	var safe_id := Text.line(id, 40)
	for l in _licenses:
		if not (l is Dictionary and l.get("id") == id):
			continue
		var url = l.get("url")
		var lower := str(url).to_lower()
		if not url is String or not (lower.begins_with("https://") or lower.begins_with("http://")) \
				or not _plain_url(url):
			return _fail("The licence %s has no usable web address." % safe_id)
		var scheme_end: int = url.find("://") + 3
		var rest: String = url.substr(scheme_end)
		var cut := rest.length()
		for ch in "/?#":
			var at := rest.find(ch)
			if at != -1 and at < cut:
				cut = at
		var href: String = url.substr(0, scheme_end).to_lower() + rest.substr(0, cut).to_lower()
		href += rest.substr(cut) if cut < rest.length() and rest[cut] == "/" else "/" + rest.substr(cut)
		href = href.replace("(", "%28").replace(")", "%29").replace("[", "%5B").replace("]", "%5D")
		return {"ok": true, "data": {
			"id": safe_id,
			"name": Text.line(str(l.get("name", "")), 80),
			"url": href,
			"attributionRequired": l.get("attributionRequired") == true,
		}}
	return _fail("%s does not list the licence %s." % [site, safe_id])


## Printable ASCII without the characters a URL parser would encode or reject, and no login.
static func _plain_url(url: String) -> bool:
	for i in url.length():
		var cp := url.unicode_at(i)
		if cp < 0x21 or cp > 0x7e or " \"'<>`\\{}|^".contains(String.chr(cp)):
			return false
	var authority := url.substr(url.find("://") + 3).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)
	return authority != "" and not authority.contains("@")


## A preview image (WebP) as a texture, or null. At most IMAGE_SLOTS load at once; failures are
## not remembered, so the next search tries again.
func fetch_image(url: String) -> Texture2D:
	if _images.has(url):
		return _images[url]
	if not _web_url(url):
		return null
	while _image_slots == 0:
		await _image_slot_free
	_image_slots -= 1
	var req := _new_request(JSON_TIMEOUT_S, IMAGE_MAX_BYTES)
	var texture: Texture2D = null
	if req.request(url, ["User-Agent: " + user_agent()]) == OK:
		var r: Array = await req.request_completed
		if r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200 and _webp_size_ok(r[3]):
			var image := Image.new()
			if image.load_webp_from_buffer(r[3]) == OK:
				texture = ImageTexture.create_from_image(image)
	req.queue_free()
	_image_slots += 1
	_image_slot_free.emit()
	if texture != null:
		if _images.size() >= IMAGE_CACHE_MAX:
			_images.clear()
		_images[url] = texture
	return texture


## Reads a WebP's width and height from its header, so a huge image is refused before decoding.
static func _webp_size_ok(b: PackedByteArray) -> bool:
	if b.size() < 30 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "WEBP":
		return false
	var chunk := b.slice(12, 16).get_string_from_ascii()
	var w := 0
	var h := 0
	if chunk == "VP8X":
		w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16))
		h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16))
	elif chunk == "VP8 ":
		w = (b[26] | (b[27] << 8)) & 0x3fff
		h = (b[28] | (b[29] << 8)) & 0x3fff
	elif chunk == "VP8L":
		var bits := b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24)
		w = 1 + (bits & 0x3fff)
		h = 1 + ((bits >> 14) & 0x3fff)
	else:
		return false
	return w > 0 and h > 0 and w <= IMAGE_MAX_SIDE and h <= IMAGE_MAX_SIDE


## Downloads one file into `dest` (an absolute path) through the counted download URL, which
## redirects to the files host. The bytes must be exactly the size and sha256 the API listed;
## a longer answer is stopped as soon as it goes past the size. On failure `dest` is removed.
func download(asset_id: int, file: Dictionary, dest: String) -> Dictionary:
	var size := int(file.sizeBytes)
	# Built from the ids rather than taken from the answer, so it is always the site's own.
	var start := _url("/assets/%d/files/%d/download" % [asset_id, int(file.id)])
	# The first answer is normally a redirect; room for its small body even when the file is tiny.
	var r := await _fetch_to(start, dest, maxi(size, 65536))
	if r.result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED or (r.code >= 300 and r.code < 400):
		DirAccess.remove_absolute(dest)
		var target := _redirect_target(start, r.headers)
		if target == "":
			return _fail("The download redirect does not point to a plain https address; stopped.")
		r = await _fetch_to(target, dest, size)
	var fail := ""
	if r.result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		fail = "File %d is larger than the %d bytes the site listed; it was not kept." % [int(file.id), size]
	elif r.result != HTTPRequest.RESULT_SUCCESS:
		fail = "The download of file %d failed. Try again in a moment." % int(file.id)
	elif r.code != 200:
		fail = "The download of file %d failed (%d)." % [int(file.id), r.code]
	else:
		var check := await _check_file(dest, size, file.sha256)
		if check != "":
			fail = check % int(file.id)
	if fail != "":
		DirAccess.remove_absolute(dest)
		return _fail(fail)
	return {"ok": true}


func _fetch_to(url: String, dest: String, limit: int) -> Dictionary:
	var req := _new_request(DOWNLOAD_TIMEOUT_S, limit)
	req.download_file = dest
	var out := {"result": HTTPRequest.RESULT_CANT_CONNECT, "code": 0, "headers": PackedStringArray()}
	if req.request(url, ["User-Agent: " + user_agent()]) == OK:
		var r: Array = await req.request_completed
		out = {"result": r[0], "code": r[1], "headers": r[2]}
	req.queue_free()
	return out


## Where a download redirect may go: https (http only when the site itself is http). A relative
## Location is resolved against the URL that sent it.
func _redirect_target(from: String, headers: PackedStringArray) -> String:
	var location := ""
	for h in headers:
		if h.to_lower().begins_with("location:"):
			location = h.substr(9).strip_edges()
	if location == "":
		return ""
	var lower := location.to_lower()
	if lower.begins_with("https://") or lower.begins_with("http://"):
		pass
	elif location.begins_with("//"):
		location = from.get_slice("://", 0) + ":" + location
	elif location.begins_with("/"):
		location = site + location
	else:
		location = from.get_slice("?", 0).get_base_dir() + "/" + location
	return location if _web_url(location) else ""


## "" when the file has exactly `size` bytes and the sha256; otherwise a message with %d for the id.
func _check_file(path: String, size: int, sha256: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "The download of file %d could not be read back."
	var got := f.get_length()
	f.close()
	if got != size:
		return "File %%d has %d bytes, not the %d the site listed; it was not kept." % [got, size]
	if await hash_file(path) != sha256:
		return "File %d does not match its sha256 checksum; it was not kept."
	return ""


## The sha256 of a file, hashed on a worker thread so a large file does not freeze the editor.
## "" when it cannot be read.
func hash_file(path: String) -> String:
	var out := [""]
	var task := WorkerThreadPool.add_task(func(): out[0] = sha256_of(path))
	# Wait a frame at a time; out of the tree (the plugin being disabled) just block until done.
	while is_inside_tree() and not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return out[0]


static func sha256_of(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1 << 20))
	return ctx.finish().hex_encode()
