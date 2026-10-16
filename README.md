# macos-debloat

A bash script that turns off the telemetry and noise macOS ships with, and can remove Apple apps you never open. Everything it changes is recorded, so one command puts it back.

Nothing happens unless you pass `--apply`. Run it bare first and look at what it wants to do.

macOS isn't Linux, so this works differently from a package-list debloater. The built-in apps (Mail, Safari, Maps...) live on the sealed system volume and can't be removed, so this doesn't try. It does three things instead:

1. **Settings**: flips `defaults` keys for ads, Siri, crash dialogs, `.DS_Store` litter and similar.
2. **Launch agents**: disables a few background agents you probably don't want (opt in).
3. **Apps**: moves removable Apple apps (GarageBand, iMovie, Keynote, Numbers, Pages) to the Trash (opt in).

## Use

```bash
git clone https://github.com/<you>/macos-debloat.git
cd macos-debloat

./debloat.sh              # preview
./debloat.sh --apply      # apply the default categories
./debloat.sh --restore    # undo the last run
```

Don't use sudo. Settings are per user, and under sudo they'd land in root's account.

```
-a, --apply             make the changes
-y, --yes               skip the confirmation
-c, --categories LIST   comma separated, or "all"
-l, --list              show categories
-r, --restore [DIR]     undo a run (default: latest)
-h, --help
-v, --version
```

```bash
./debloat.sh -c telemetry -a            # only telemetry settings
./debloat.sh -c agents -a               # disable the background agents
./debloat.sh -c apple-office,apple-creative -a
./debloat.sh -c all -a -y
```

## Categories

| Category | What | Default |
|---|---|---|
| `telemetry` | personalised ads, Siri query sharing, crash report dialog | yes |
| `siri` | turn Siri off, hide it from the menu bar | yes |
| `annoyances` | no .DS_Store on network/USB, no recent apps in the Dock, save to disk not iCloud, Time Machine nag | yes |
| `agents` | rcd, photoanalysisd, suggestd, assistantd, ... | no |
| `apple-creative` | GarageBand, iMovie | no |
| `apple-office` | Keynote, Numbers, Pages | no |

The lists are plain text in `data/`, one entry per line.

## Undo

Each run saves what it changed to `~/.macos-debloat/<timestamp>/`.

- Settings go back to their old value, or are deleted if they weren't set before.
- Agents are re-enabled and come back at your next login.
- Apps are moved from the Trash back to where they were. If you've already emptied the Trash, get them again from the App Store.

## Heads up

- I wrote and tested this against stubbed `defaults` and `launchctl`, not on a real Mac. The CI job runs it on a real macOS runner (dry run only), but check the preview on your own machine before applying.
- Apple moves and renames these keys between macOS versions. If a setting doesn't do anything on your version, it's harmless, just ineffective.
- Writing to some preference domains may need your terminal to have Full Disk Access (System Settings > Privacy & Security).
- Some changes need a logout or a restart before you see them. Dock and Finder are restarted automatically.
- Apps that are root owned may fail to move; the script tells you the `sudo mv` to use.
- Diagnostics sharing (Analytics & Improvements) is a system-wide setting this doesn't touch. Turn it off in System Settings > Privacy & Security > Analytics & Improvements.
- Your Mac, your call. Read the preview.

## Tests

```bash
bash tests/smoke.sh
bash tests/test_stubbed.sh
```

The second one runs a full dry run / apply / restore cycle against fake `defaults`, `launchctl`, `/Applications` and Trash.
