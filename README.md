# Kodogu add-on for Godot

A Godot 4 editor plugin (GDScript only, no native code) that adds a **Kodogu** screen next to 2D,
3D and Script. From there you search and browse Kodogu props (preview, licence, formats, files and
the "contains scripts" flag) and install one into the open project.

It does what Kodogu's command-line tool (`kodogu add`) does, with the same paths and credit text:

- files go to `res://assets/<slug>/`, with the CLI's safe file names;
- the credit line goes into `CREDITS.md` at the project root, once per prop; from a prop's second
  version on it names the version, and installing a newer version replaces the prop's line (a
  line you edited after its URL is left alone);
- it installs a prop's current version; for an earlier one (`?version=<n>` in a pasted page URL,
  or `<id>@<n>`) it says so and points to the prop's page, where every listed version can be
  downloaded;
- each download must match the size and sha256 the API lists, or it is not kept;
- a prop with scripts is installed only after a warning; nothing from a prop is opened, extracted
  or run; zip archives stay zipped;
- a link (symlink or junction) on the way to `res://assets/<slug>/` or in place of `CREDITS.md`
  stops the install before anything is read or written there (the CLI allows a link that stays
  inside the project; the add-on refuses them all);
- a `CREDITS.md` that is not clean UTF-8 (UTF-16, stray bytes) is left alone rather than
  rewritten; the add-on then asks you to add the line yourself.

It reads the public REST API (`/api/v1/*`) anonymously, with `reviewedOnly=true` like the CLI and
agents. Favourites and collections are not in it: personal API tokens work on the MCP server only,
not on the REST API, so that would need an API change first.

Tested with Godot 4.7.2 on Windows, links and junctions included. It uses nothing newer than
Godot 4.2, but the link refusal depends on `DirAccess.is_link`, which has only been checked on
4.7.2: on an older Godot, run `test/test_install.gd` first.

## Installing it in a project

1. Download the latest release from
   [github.com/benexus/kodogu-godot/releases](https://github.com/benexus/kodogu-godot/releases)
   and copy its `addons/kodogu/` folder into the project, so that `res://addons/kodogu/plugin.cfg`
   exists.
2. **Project → Project Settings → Plugins**: enable **Kodogu**.
3. Press **Kodogu** at the top of the editor.

The site is in `plugin.cfg` (`[kodogu] site`). **Editor Settings → Kodogu → Site** overrides it,
for example `http://localhost:8787` for a local dev server (http only for this computer).

## Files

| File                              | What it is                                                        |
| --------------------------------- | ----------------------------------------------------------------- |
| `addons/kodogu/plugin.gd`         | The editor plugin: the Kodogu screen and the site setting.        |
| `addons/kodogu/kodogu_browser.gd` | Search, the prop grid, the prop's details and Install.            |
| `addons/kodogu/kodogu_api.gd`     | The REST client: checks answers, loads previews, downloads.       |
| `addons/kodogu/kodogu_install.gd` | Where files go, link checks, partial files, CREDITS.md.           |
| `addons/kodogu/kodogu_text.gd`    | The CLI's file-name and credit-line rules, ported to GDScript.    |
| `addons/kodogu/kodogu_fold.gd`    | Generated: the Unicode folding the file-name rules need.          |
| `project.godot`                   | A small project for trying the add-on; open this folder in Godot. |
| `test/`                           | The tests below.                                                  |
| `media/`                          | The Asset Store's thumbnail and screenshots (not in any zip).     |
| `STORE.md`                        | The Asset Store listing's text and fields.                        |

## Tests

From this folder (`addons/godot`), with Godot on the PATH (`godot_console` on Windows):

```sh
# The GDScript port gives the same file names and credit lines as the TypeScript (no network).
godot --headless --path . --script res://test/test_text.gd

# Links, junctions and odd CREDITS.md encodings are refused, and nothing is written outside the
# stand-in project (no network). Symbolic links need Developer Mode or admin rights on Windows.
godot --headless --path . --script res://test/test_install.gd -- <empty folder>

# End to end against the live site: search, previews, install, a second install, and refused
# downloads with a wrong size or checksum. Installs into the folder given; counts as a download.
godot --headless --path . --script res://test/test_live.gd -- <empty folder> <prop id>...

# The add-on's scripts raise none of Godot's default warnings (no network). Godot hides warnings
# under res://addons/, so this parses them in a probe project built in the folder given.
godot --headless --path . --script res://test/test_warnings.gd -- <empty folder>
```

`kodogu_fold.gd` and `test/vectors.json` are generated from the TypeScript rules in Kodogu's own
repository; do not edit them by hand. There, after changing `safeFileName`, `creditLine`,
`markdownText` or `withCredit`, run `node scripts/godot-addon-data.mjs` from the repository root
to rewrite both, then run `test_text.gd` again. The CLI's tests
(`packages/cli/test/godot-addon-data.test.ts`) fail while these files are out of date.

## Licence and releases

MIT; see [LICENSE](LICENSE) (a copy travels in `addons/kodogu/`).

The add-on lives in `addons/godot/` of Kodogu's own repository, which is private.
[github.com/benexus/kodogu-godot](https://github.com/benexus/kodogu-godot) is its public copy:
each release is copied there as one commit and tagged with the version in `plugin.cfg`. GitHub's
download zip of a tag holds only `addons/kodogu/`, this README and the licence
(`.gitattributes` leaves out the test project).

To release, from the Kodogu repository root, with a clone of kodogu-godot next to it:

```sh
# 1. Raise `version` in addons/godot/addons/kodogu/plugin.cfg and merge that to main.
# 2. Replace the public copy's files with addons/godot as committed on main (staged, not committed).
node scripts/godot-addon-release.mjs ../kodogu-godot main
# 3. Commit as Indie Software, tag the version and push.
git -C ../kodogu-godot -c user.name="Indie Software" commit -m "Kodogu add-on <version>"
git -C ../kodogu-godot tag v<version>
git -C ../kodogu-godot push origin main v<version>
```

For the [Godot Asset Store](https://store.godotengine.org), which Godot 4.7's editor browses, run
`test/test_warnings.gd` before releasing (the store asks for scripts without warnings), then build
its zip, which holds `addons/kodogu/` and nothing else, from the tag, and upload it as a new
version (version name, changelog, minimum Godot 4.7). `STORE.md` has the listing's text.

```sh
git -C ../kodogu-godot archive --format=zip -o ../kodogu-godot-<version>.zip v<version> addons/kodogu
```
