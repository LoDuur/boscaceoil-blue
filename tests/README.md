# Headless tests

These suites run the app headlessly with Godot 4.3 and GDSiON. The `.gdignore`
file keeps this folder out of the editor's file system and out of exported
builds; the scenes are still loadable by path.

## Requirements

- Godot 4.3 (`godot` on the `PATH`, or set `GODOT=/path/to/godot`).
- GDSiON 0.7 extracted into `bin/`, as described in the main README under
  "Notes for developers".

## Running

```
tests/run_tests.sh            # every suite
tests/run_tests.sh --strict   # also treat GDScript warnings as errors
```

A single suite can be run directly:

```
godot --headless --quit-after 20000 res://tests/Phase3Tests.tscn
```

Suites write scratch files as `user://test_*` and delete them when they finish.
The custom instrument library test only touches the files it creates.

## Suites

| Suite | Covers |
|-------|--------|
| `CheckAll` | Every app script compiles and every scene loads. |
| `Phase1Tests` | Random voice pool (500 rolls, no percussion, no repeats), legacy recording data skipped on load. |
| `Phase2Tests` | Selection, clipboard and ghost placement data classes. |
| `Phase3Tests` | Note editor on the real `Main.tscn`: keyboard selection, nudges, cut/copy/paste/duplicate, the 128-note limit, drags, shifts and rotation, drum patterns. |
| `Phase4Tests` | Arrangement on the real `Main.tscn`: moves, copy/paste, delete, drag move/copy/variant, focus release. |
| `Phase5Tests` | File format v4: byte-identical round trip, invalid files rejected, v3 upgrade. |
| `Phase6Tests` | Custom instruments: voice building, preset isolation, clamping, undo, randomize, round trip, library. |
| `Phase6UiTests` | CUSTOM category in the type drop-down (no dock button) and the sound panel on the real `Main.tscn`. |
| `Phase6WavTests` | WAV export with a custom instrument is audible and identical after save and reload. |
| `Phase7Tests` | Removing unused patterns (with undo/redo) and the follow-playback toggle. |
| `ValueSliderTests` | The slider widget (silent set, commit on drag end, held-key settling, live mode, clamping) and its use for BPM, pattern size, bar size and swing; the filter/volume pads stay pads. |
| `HelpTests` | Every shortcut on the Help page resolves to a real binding. |
