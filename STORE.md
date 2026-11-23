# Godot Asset Store listing

What to enter on [store.godotengine.org](https://store.godotengine.org) for the Kodogu add-on, per
the store's [submission guide](https://docs.godotengine.org/en/stable/community/asset_store/submitting_to_asset_store.html)
and [guidelines](https://store.godotengine.org/guidelines/). Godot 4.7's editor browses this store
(its **Asset Store** tab); the older Asset Library is for older Godot versions.

The store takes an uploaded zip, not a Git link. The zip holds `addons/kodogu/` and nothing else;
the licence travels inside it (`addons/kodogu/LICENSE`). Build it from the public repository's
tag (see "Licence and releases" in the README).

## Upload Asset page

| Field              | Value           |
| ------------------ | --------------- |
| Publisher          | (new publisher) |
| Publisher Name     | Indie Software  |
| Publisher URL Slug | indie-software  |
| Asset Name         | Kodogu          |
| Asset URL          | kodogu          |

## Settings

**Asset Summary**

Search the Kodogu prop library from the editor and install a prop into your project, with its
licence credited in CREDITS.md.

**Description**

Kodogu is a free library of 3D models, scenes and projects for Godot and Blender. This add-on
adds a Kodogu screen to the editor, next to 2D, 3D and Script, so you can find and install props
without leaving Godot.

- Search the library, filter by format and engine, and sort the results.
- See each prop's preview, licence, formats, files, polygon count and AI-use label, and whether
  it contains scripts.
- Paste a prop's page address or id to open it straight away.
- Install a prop with one button: its files go to res://assets/<prop>/ and its credit line is
  added to CREDITS.md in your project folder, once per prop.

Downloads are checked against the size and SHA-256 checksum the library lists, and a file that
does not match is not kept. A prop that contains scripts is clearly marked, and the add-on asks
before installing it. The add-on never opens, extracts or runs what it downloads. Zip archives
stay zipped. Symbolic links and junctions in the way are refused, so nothing is written outside
your project.

The add-on needs no account and collects nothing. It only talks to the Kodogu site
(kodogu.indiesoftware.dev, or another one you set in Editor Settings): it sends your searches
and downloads the props you install. Nothing about your project is sent.

Written in GDScript only, with no native code. Tested with Godot 4.7.2.

**Tags** (not the asset's name, no singular and plural pairs)

3d-models, asset-browser, credits, creative-commons, downloader, library

**Asset type:** Addon

**License:** MIT

**Link to source code:** https://github.com/benexus/kodogu-godot

**AI usage disclosure**

The add-on's code, tests and texts were written with Claude, an AI model by Anthropic, directed
by Indie Software, and checked with automated tests in Godot 4.7.2 (file-name and credit rules,
link refusals, a live install from the Kodogu site, and a check that the scripts raise no
warnings). The thumbnail and screenshots are real captures of the add-on in Godot 4.7.2.

## Media

Direct links (GitHub images must come from raw.githubusercontent.com). The thumbnail is 16:9.

| Item       | Link                                                                                       |
| ---------- | ------------------------------------------------------------------------------------------ |
| Thumbnail  | https://raw.githubusercontent.com/benexus/kodogu-godot/main/media/thumbnail.png            |
| Screenshot | https://raw.githubusercontent.com/benexus/kodogu-godot/main/media/screenshot-browse.png    |
| Screenshot | https://raw.githubusercontent.com/benexus/kodogu-godot/main/media/screenshot-installed.png |

## Versions

| Field                 | Value                                                   |
| --------------------- | ------------------------------------------------------- |
| Version name          | the `version` in `addons/kodogu/plugin.cfg`, e.g. 0.1.2 |
| Minimum Godot version | 4.7                                                     |
| File                  | kodogu-godot-<version>.zip                              |

Changelog for 0.1.2, the first store version:

First release on the Godot Asset Store. Search and browse Kodogu props in the editor and install
them with their credit line in CREDITS.md; downloads are checked against their SHA-256 checksums.
Supports prop versions: from a prop's second version on, the credit line names the version, and
installing a newer version updates the prop's line.

## Pricing

Free. No donation link. Reviews left on.
