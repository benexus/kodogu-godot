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
- Install a prop with one button: its files go to `res://assets/<prop>/` and its credit line is
  added to `CREDITS.md` in your project folder, once per prop.

(The form renders Markdown: keep the backticks, or `<prop>` disappears and `CREDITS.md` becomes a
link.)

Downloads are checked against the size and SHA-256 checksum the library lists, and a file that
does not match is not kept. A prop that contains scripts is clearly marked, and the add-on asks
before installing it. The add-on never opens, extracts or runs what it downloads. Zip archives
stay zipped. Symbolic links and junctions in the way are refused, so nothing is written outside
your project.

The add-on needs no account and collects nothing. It only talks to the Kodogu site
(kodogu.indiesoftware.dev, or another one you set in Editor Settings): it sends your searches
and downloads the props you install. Nothing about your project is sent.

Written in GDScript only, with no native code. Tested with Godot 4.7.2.

Questions and problems: open an issue at https://github.com/benexus/kodogu-godot/issues.

**Tags** (not the asset's name, no singular and plural pairs)

3d-models, asset-browser, credits, creative-commons, downloader, library

**Asset type:** Addon

**License:** MIT

**Source Code URL:** https://github.com/benexus/kodogu-godot

**Documentation URL:** https://kodogu.indiesoftware.dev/help#godot-addon

**This asset uses AI generated assets and/or code:** ticked.

**AI usage disclosure**

The add-on's code, tests and texts were written with Claude, an AI model by Anthropic, directed
by Indie Software, and checked with automated tests in Godot 4.7.2 (file-name and credit rules,
link refusals, a live install from the Kodogu site, and a check that the scripts raise no
warnings). The thumbnail and screenshots are real captures of the add-on in Godot 4.7.2; the
prop they show, the Kodogu Mascot, is a 3D model made with AI assistance (Claude, through the
Blender MCP server), as its own page on Kodogu says. The add-on ships no models or images.
Props in the Kodogu library are made by their uploaders, and each one shows its own AI-use
label, which the add-on displays.

## Media

Uploaded files: 16:9, 1920×1080 recommended (1280×720 minimum), WebP recommended, 600 KB at
most each. All three in `media/` are 1920×1080 WebP.

| Item            | File                              |
| --------------- | --------------------------------- |
| Store Thumbnail | `media/thumbnail.webp`            |
| Featured Image  | (empty: the thumbnail is used)    |
| Media           | `media/screenshot-browse.webp`    |
| Media           | `media/screenshot-installed.webp` |
| Video           | (none)                            |

The thumbnail is the Kodogu Mascot (the site's own render of prop 1), the site's logo and name,
and one line on what the add-on does. `media/make_thumbnail.py` builds it from that render and
the site's Archivo font (`node_modules/@fontsource-variable/archivo`). The screenshots are real
captures of the add-on in Godot 4.7.2 against the live site.

## Versions

| Field                 | Value                                                   |
| --------------------- | ------------------------------------------------------- |
| Version name          | the `version` in `addons/kodogu/plugin.cfg`, e.g. 0.1.3 |
| Minimum Godot version | 4.7                                                     |
| File                  | kodogu-godot-<version>.zip                              |

Changelog for 0.1.3, the first store version:

First release on the Godot Asset Store. Search and browse Kodogu props in the editor and install
them with their credit line in CREDITS.md; downloads are checked against their SHA-256 checksums.
Supports prop versions: from a prop's second version on, the credit line names the version, and
installing a newer version updates the prop's line.

## Pricing

Free. No donation link. Reviews left on.

## Store terms

Checked on 2026-11-23 against the [terms](https://store.godotengine.org/terms/) (Godot
Foundation, Netherlands law), [guidelines](https://store.godotengine.org/guidelines/) and
[help](https://store.godotengine.org/help/). The terms may change; look again before each new
version.

- **Rights granted:** publishing gives the Godot Foundation a worldwide, sublicensable licence to
  host, redistribute and promote the add-on and its media while the account exists (and one month
  after), and gives users a perpetual licence to use and modify it. The MIT licence already allows
  all of that; Indie Software keeps ownership.
- **Licence with the download:** `addons/kodogu/LICENSE` holds the MIT text and "Copyright (c)
  2026 Indie Software", matching the listing's licence.
- **Contact and support:** publishers must let users contact them and handle their own support.
  The description points to the GitHub issues, which are on; someone needs to watch them.
- **AI disclosure:** required for AI-made code or content; given above, including the AI-assisted
  model in the screenshots.
- **Accurate listing:** thumbnail and screenshots are real captures; no fabricated features.
- **No prohibited content:** no malware, no executables or native libraries, no infringing
  content. The add-on is our own code; the props it downloads come from the Kodogu site under
  their own licences and are not uploaded to the store.
- **Works, no warnings, addons/ layout, under 1 GB:** checked by `test/test_warnings.gd`, the
  other tests, and installing the zip into an empty Godot 4.7.2 project.
- **Publisher:** the person who registers must have legal capacity and give full and accurate
  account information. Publishing under the trade name Indie Software is not restricted. Paid
  assets and taxes do not apply to a free asset.
- **Indemnity:** the publisher answers to the Foundation for any rights infringement in what it
  uploads.
