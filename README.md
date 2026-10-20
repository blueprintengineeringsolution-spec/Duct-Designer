# Ductletor Pro

Offline-first HVAC duct design, sizing and reporting app (Flutter), with a pure-Dart calculation engine.

## Layout
- `packages/hvac_engine/` pure Dart: friction and sizing (equal friction, static regain, velocity reduction, constant velocity), round and rectangular sizes with standard-size recommendations, fittings, critical path, noise screening, BOQ, project file format and share codes, measurement helpers. Has its own tests (`dart test`).
- `lib/` Flutter app: state (`state/`), storage (`data/`), screens (`features/`).
- `test/` Flutter tests.

## First run
This archive has no platform folders. In an empty copy of the project:

    flutter create .          # generates android/ ios/ etc. (keeps existing lib/ and pubspec.yaml)
    flutter pub get
    flutter test
    (cd packages/hvac_engine && dart pub get && dart test)
    flutter run

Written against a recent Flutter (3.27 or later, Dart 3.3 or later).

## Platform setup still needed
- Camera permission for the QR scanner and AR (Android manifest CAMERA; iOS NSCameraUsageDescription).
- AR measuring uses `ar_flutter_plugin`, which is poorly maintained. If it will not build, replace the body of `lib/features/measure/ar_measure_view.dart` with a call to `onUnavailable`; typed tape readings keep working.
- Fitting libraries can be exported (`.ductlib`) and imported from Settings. Opening `.ductletor` / `.ductlib` files from other apps is not registered; use Projects > Import.

## Status
Nothing in this archive has been compiled or run by the author (no Dart or Flutter available when it was written). Expect a few compile fixes and test adjustments on first run.

## Engineering caveats
- Built-in elbow, reducer and junction coefficients, the noise model and the flex-duct factor are screening values, not ASHRAE Duct Fitting Database data (that database is licensed). Use Sourced C or Table fittings with your own licensed data and turn on "Flag built-in coefficients" in Settings.
- AR length measurements are estimates (roughly 2% plus 1 cm per tap); confirm with a tape before ordering material.

## Running the tests
    flutter pub get
    flutter test                                   # app tests (test/)
    cd packages/hvac_engine && dart pub get && dart test    # engine tests

If something fails, the first error line and the test name are enough to fix it.
Some numeric test expectations (for example the equal-friction sizes and standard-size snapping) were
cross-checked against a separate Python port of the math; the rest were not run.

## Running in Chrome
    flutter run -d chrome
Works for trying the screens. In the browser: projects are kept in browser storage (about 5 MB, cleared with site data);
project, library and BOQ (CSV) files download from the browser (Import > Paste still works with copied text); PDF export downloads; AR is not available
(tape readings work); QR scanning needs camera permission and localhost or https.

## Units and splits
- A project can hold several units (air handling units, each its own duct network and fan). Use the chips above the tree or schematic to switch, the + button to add one, and the menu beside it to rename, duplicate or delete the active unit. Reports and the bill of quantities cover every unit.
- Wherever a section splits into two or more children, a fitting is added automatically (a 90 degree tee unless you change it in Settings, or on that section). The tee is charged once, on the outlets, not on the parent. It shows as a dot on the schematic and a row in the tree.
- On the schematic, tap a section to select it: a bar offers Edit, Add child, Add fitting, Duplicate, Delete and Collapse, and a + handle beside the section adds a child.

## Editing the network
There is no separate tree view: the diagram is the editor. Tap a section to select it and double-tap to open it (name, shape, size, flow, length, material, fittings, split type; add child, add fitting, duplicate, delete, collapse); the Edit section button does the same for the selected section. Double-tap empty space to fit the diagram to the screen. The + handle beside a selected section adds a child quickly, and long-press collapses or expands a branch. Change a section's name in the field at the top of its editor.

## Unit status
Each unit chip has a dot for its worst section (green OK, amber caution, red over limit); press and hold, or use a screen reader, for the wording and the number of warnings. With more than one unit, the Report tab opens with a list of units (status, fan pressure, duct length, warnings); tap one to open it.

## Warnings
The warning triangle in the top bar shows how many warnings the whole project has. It opens one list (over-limit sections first, grouped by unit); tap a warning to switch to that unit and open the section for editing.
