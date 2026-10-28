# Kero Cabinet

**A parametric cabinet builder for SketchUp.** Enter dimensions and a bay layout to create an editable cabinet component.

Version: **v0.4.0 (early development)**. The original project reports use in SketchUp 2025. Automated tests use a mock SketchUp API; they are not runtime integration tests.

## Features

- Width, height, depth, panel and back thickness, toe kick, and front gaps
- Full-height sides with top/bottom between them, or full-width top/bottom with sides between them
- Optional face frame and inset or overlay fronts
- 1-6 vertical bays with relative width weights
- Door, drawer (1-8 drawers), and open-shelf bays
- Separate SketchUp components for individual wooden parts
- Edit existing cabinets using their saved parameters
- Full-width back panel applied outside the case
- English interface, validation errors, generated part/material names, documentation, and tests

The plugin does not generate cut lists. Separate part components are intended for use with [OpenCutList](https://www.opencutlist.org/); end-to-end compatibility has not been tested.

## Installation

1. Download the RBZ from the `kero-cabinet-rbz` artifact of a successful GitHub Actions run, or build it locally.
2. In SketchUp, open **Extensions > Extension Manager > Install Extension**.
3. Select `Kero_Cabinet_v0.4.0.rbz` and restart SketchUp.
4. Choose **Extensions > Kero Cabinet > Create new cabinet...**.

To edit a cabinet, select its component and choose **Kero Cabinet | Edit parameters** from the context menu, or **Edit selected cabinet...** from the extension menu.

## Updates from GitHub

Install v0.4.0 once using the RBZ. Future releases can be installed from
**Extensions > Kero Cabinet > Check for updates...**, without downloading or
installing another RBZ manually. Save your work and restart SketchUp after an update.

The public `keremdemirer/kero-cabinet` repository requires no token or Git installation.
The plugin checks `main` in the background at startup and offers newer versions.
Disable startup checks under **Update settings...**. Startup network errors stay
quiet; manual checks display errors. Updates always require your confirmation.

Downloads use HTTPS, one fixed repository revision, and SHA-256 verification.
Only the three plugin Ruby files listed in `update.json` can be replaced.
Files are staged before replacement; handled installation failures restore the
previous files. Do not close SketchUp while installation is in progress.
The plugin directory must be writable. Symlink installations are not supported.
The updater does not change existing cabinet geometry or save your open model.

For each release, increase the version in both Ruby entry files, run
`python3 scripts/update_manifest.py`, test, and commit all files together.
Only version increases are offered; ordinary commits at the same version are
not installed automatically. This is a source updater for this unsigned extension;
it does not preserve Extension Warehouse signatures. Runtime testing in SketchUp
is still required. Future additional plugin assets require an updater migration.

Internal shelves behind inset doors start behind the door back with the configured gap. Their rear edges remain aligned with the case; open shelves keep their original depth.

## Toe kick timber support frame

Enabled by default with **50 x 100 mm timber, 100 mm upright**. Full-width front
and rear rails enclose side and cross rails using square butt joints. The frame
starts directly behind the existing toe kick front panel and reaches the rear
of the case. Each bay boundary has a cross rail; spans over 600 mm receive extra
cross rails. Every timber member is a separate component.

At the default 100 mm toe height, the frame rests on the floor and its top
contacts the case bottom. Taller toe spaces receive vertical timber legs under
the front/rear rails. A positive toe height below the upright timber height is
rejected; lower the timber height or disable the support frame. At zero toe
height, neither a toe kick front nor a support frame is created. The editor lets
you change timber thickness, upright height, or disable the support frame.
Existing cabinets receive the new defaults when edited. Existing toe heights
below 100 mm need one of these adjustments before regeneration.

## Dimensions

All design inputs are in **millimetres**.

- **Width:** Overall case width.
- **Height:** Total height including the toe kick.
- **Depth:** Distance to the rear edge of the case, excluding back panel and front thickness.
- **Back panel:** Applied outside the case; adds its thickness to the overall depth.
- **Full-height sides:** Top and bottom widths equal `overall width - 2 * panel thickness`.

## Project structure

```text
kero_cabinet.rb             # SketchUp extension registration
kero_cabinet/core.rb        # Parameters, interface, and geometry
kero_cabinet/updater.rb     # Public GitHub updates
update.json                # Version and file checksums
scripts/build.sh           # RBZ packaging
scripts/check_english.py   # English text regression guard
test/geometry_test.rb      # Mock SketchUp geometry tests
test/updater_test.rb       # Update verification and rollback tests
.github/workflows/ci.yml   # Tests and packaging
CHANGELOG.md               # Release notes
SOURCE_PROVENANCE.md       # Original file verification
```

## Development and verification

Requires Ruby 2.6 or newer, Python 3, zip, and unzip. CI uses Ruby 3.3.

```bash
python3 scripts/check_english.py
ruby -c kero_cabinet.rb
ruby -c kero_cabinet/core.rb
ruby test/geometry_test.rb
ruby test/updater_test.rb
python3 scripts/update_manifest.py --check
bash scripts/build.sh
```

Output: `dist/Kero_Cabinet_v0.4.0.rbz`.

CI checks text, Ruby syntax, 25 geometry configurations, and archive integrity on pushes and pull requests. Successful runs upload the installation package.

## Existing models

Stored configuration keys and enum values remain compatible. Existing user-entered cabinet names are preserved; rename them in the editor if desired. Regenerating a cabinet replaces its generated parts with English names. Old unused component definitions or materials already stored in a SketchUp model are not purged.

## Limitations

- No hinge holes, runner models, or joinery details.
- Drawer boxes use simple rectangular panels.
- Not every dimension combination or manufacturing tolerance has been verified in SketchUp.
- Runtime UI and OpenCutList integration require manual testing in SketchUp.

## License

No license has been selected. No new license is added by this translation.
