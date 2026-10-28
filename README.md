# Kero Cabinet

**A parametric cabinet builder for SketchUp.** Enter dimensions and a bay layout to create an editable cabinet component.

Version: **v0.2.2 (early development)**. The original project reports use in SketchUp 2025. Automated tests use a mock SketchUp API; they are not runtime integration tests.

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
3. Select `Kero_Cabinet_v0.2.2.rbz` and restart SketchUp.
4. Choose **Extensions > Kero Cabinet > Create new cabinet...**.

To edit a cabinet, select its component and choose **Kero Cabinet | Edit parameters** from the context menu, or **Edit selected cabinet...** from the extension menu.

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
scripts/build.sh           # RBZ packaging
scripts/check_english.py   # English text regression guard
test/geometry_test.rb      # Mock SketchUp geometry tests
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
bash scripts/build.sh
```

Output: `dist/Kero_Cabinet_v0.2.2.rbz`.

CI checks text, Ruby syntax, 16 geometry configurations, and archive integrity on pushes and pull requests. Successful runs upload the installation package.

## Existing models

Stored configuration keys and enum values remain compatible. Existing user-entered cabinet names are preserved; rename them in the editor if desired. Regenerating a cabinet replaces its generated parts with English names. Old unused component definitions or materials already stored in a SketchUp model are not purged.

## Limitations

- No hinge holes, runner models, or joinery details.
- Drawer boxes use simple rectangular panels.
- Not every dimension combination or manufacturing tolerance has been verified in SketchUp.
- Runtime UI and OpenCutList integration require manual testing in SketchUp.

## License

No license has been selected. No new license is added by this translation.
