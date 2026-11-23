@tool
extends EditorPlugin

## Adds a "Kodogu" screen next to 2D, 3D, Script and AssetLib.

const Browser := preload("kodogu_browser.gd")
const SITE_SETTING := "kodogu/site"

var _browser: Control


func _enter_tree() -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(SITE_SETTING):
		settings.set_setting(SITE_SETTING, "")
	settings.set_initial_value(SITE_SETTING, "", false)
	settings.add_property_info({
		"name": SITE_SETTING,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_PLACEHOLDER_TEXT,
		"hint_string": _default_site(),
	})
	_browser = Browser.new()
	_browser.site_value = _site
	EditorInterface.get_editor_main_screen().add_child(_browser)
	_make_visible(false)


func _exit_tree() -> void:
	if _browser:
		_browser.queue_free()
		_browser = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _browser:
		_browser.visible = visible


func _get_plugin_name() -> String:
	return "Kodogu"


func _get_plugin_icon() -> Texture2D:
	# "AssetStore" in Godot 4.7, "AssetLib" before.
	var theme := EditorInterface.get_editor_theme()
	for icon in ["AssetStore", "AssetLib"]:
		if theme.has_icon(icon, "EditorIcons"):
			return theme.get_icon(icon, "EditorIcons")
	return null


## The site from Editor Settings, or the one in plugin.cfg.
func _site() -> String:
	var value := str(EditorInterface.get_editor_settings().get_setting(SITE_SETTING)).strip_edges()
	return value if value != "" else _default_site()


func _default_site() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(get_script().resource_path.get_base_dir().path_join("plugin.cfg")) != OK:
		return ""
	return str(cfg.get_value("kodogu", "site", ""))
