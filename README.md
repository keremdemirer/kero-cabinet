# Kero Cabinet

**A parametric cabinet builder for SketchUp.** Enter dimensions and a bay layout to create an editable cabinet component.

Version: **v0.7.0 (early development)**. The original project reports use in SketchUp 2025. Automated tests use a mock SketchUp API; they are not runtime integration tests.

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
3. Select `Kero_Cabinet_v0.7.0.rbz` and restart SketchUp.
4. Choose **Extensions > Kero Cabinet > Create new cabinet...**.

To edit a cabinet, select its component and choose **Kero Cabinet | Edit parameters** from the context menu, or **Edit selected cabinet...** from the extension menu.

## Updates from GitHub

Install v0.7.0 once using the RBZ. Future releases can be installed from
**Extensions > Kero Cabinet > Check for updates...**, without downloading or
installing another RBZ manually. Save your work and restart SketchUp after an update.

The public `keremdemirer/kero-cabinet` repository requires no token or Git installation.
The plugin checks `main` in the background at startup and offers newer versions.
Disable startup checks under **Update settings...**. Startup network errors stay
quiet; manual checks display errors. Updates always require your confirmation.

Downloads use SketchUp native asynchronous HTTPS, one fixed repository revision,
and SHA-256 verification. Requests time out after 40 seconds. Ruby TLS is used
only outside the native SketchUp transport environment.
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

### Update connection troubleshooting

Internet access in a browser does not prove that SketchUp can reach GitHub.
From v0.7.0 the updater uses SketchUp's native HTTP transport and reports the
actual failure category. Check application firewall/proxy/VPN settings when
SketchUp cannot reach `api.github.com`. Certificate checks are never disabled.
If an older updater cannot download this fix, install the current RBZ once via
Extension Manager and restart SketchUp before checking again. Native HTTP tests
use mocks; a runtime check on the affected SketchUp installation is still needed.

## Stacked horizontal sections

In a vertical bay, choose **Mixed layout** to place different contents
above one another. The default is one bottom drawer and an upper door section,
with height weights **1:3**. Each bay supports **2-6** sections displayed top to
bottom to match the cabinet. Stored section order remains bottom to top. Each section can contain drawers, doors, or open shelves. Use **Up/Down**
to reorder them and **Add section above** to extend the layout.

Height weights divide the available internal height. Horizontal divider panels
use case material and thickness. Face-frame models also receive horizontal face
rails. Front clearances, shelf setbacks, and drawer boxes respect each section's
bounds. Sections too short for their contents are rejected with an English error.
Existing single-type bays remain unchanged until Mixed layout is selected.

The Cabinet layout editor uses direct Doors / Drawers / Open shelves / Mixed layout
buttons. Mixed bays show a top-to-bottom schematic, height percentages alongside
ratios, and quick Drawer + doors / Equal split / 3 sections presets. Presets replace
the selected bay's section layout when clicked. Width ratios are shown only when
there is more than one bay. Move and remove buttons have explicit accessible labels.

Numeric inputs show their limits and reject empty or out-of-range values before
submission. Error messages identify the field and entered value. Toe kick height
is **0-250 mm**, upright timber height **20-200 mm**, and timber thickness
**10-100 mm**. Defaults are **100, 100, and 50 mm**, respectively. Mouse-wheel
scrolling blurs focused number inputs to avoid accidental value changes.

## Top, bottom, and back construction

In **Top / Bottom / Back construction**, select **Full panel** or **Support rails**
independently for the top and back. Defaults remain full panels for existing models.
Rails use the case material and thickness, with a default width of **100 mm**.

Top rails are horizontal at the front and rear. Back rails are vertical at the
upper and lower rear edges, between the side panels. When both are selected,
the upper rear rails meet as an L without overlapping. Side panels automatically
extend to the cabinet top and the top-arrangement selector is locked.
The bottom panel remains solid and is selected independently: **Between sides**
or **Full width**. With Full width, sides start on the bottom panel, one panel
thickness higher, preserving the overall cabinet height. Legacy bottom choices
are preserved when older cabinets are edited. Internal dividers and shelves stop before the back rails.
With back rails there is no external back panel; the side depth uses the full
requested depth. Oversized rails that cannot fit are rejected.

## Drawer construction

**Drawer box thickness** controls the sides and front/back box members;
**Drawer bottom thickness** controls the bottom independently. Both default to
**12 mm**. The bottom fits between the four box members. Stock changes preserve
the outer box dimensions and side clearances for the selected runner profile. Visible drawer
fronts still use the existing Door/front thickness setting. Bottom stock that
cannot fit inside the box is rejected. These settings apply to all drawer bays.

### Shallow drawers and side-mount slide profiles

Choose **Drawer slide profile** under Drawer construction. The default Easy-close
profile uses a 47.7 mm minimum box height and 13.5 mm side clearance (3832EC
reference). Low-profile uses a 35.1 mm minimum box height and 13.0 mm side
clearance (2132C reference). These rounded minimum heights come from manufacturer
minimum drawer-height requirements, not merely slide-body dimensions.

The old fixed 100 mm section / 85 mm front / 60 mm box limits no longer apply
to drawers. Box height adapts to available space up to the existing 125 mm
preferred height. Kero Cabinet reserves 4 mm above and below the box and at least
10 mm usable above its bottom. These are application allowances, not manufacturer
specifications. Sections still need room for front/frame margins and dividers.
Errors report the available front/opening and required height.

Profiles cover minimum height and side space only. They do not certify hardware
compatibility: slide length increments, maximum width, loads, mounting brackets,
setbacks, fasteners and holes must follow the exact product data. Undermount
systems are not covered. See [Hardware references](HARDWARE.md).

## Toe kick timber support frame

Enabled by default with **50 x 100 mm timber, 100 mm upright**. Full-width front
and rear rails enclose side and cross rails using square butt joints. The frame
starts directly behind the full-width toe kick front panel and reaches the rear
of the case. Each bay boundary has a cross rail; spans over 600 mm receive extra
cross rails. Every timber member is a separate component.

At the default 100 mm toe height, the frame rests on the floor and its top
contacts the case bottom. Taller toe spaces receive vertical timber legs under
the front/rear rails. A positive toe height below the upright timber height is
rejected; lower the timber height or disable the support frame. At zero toe
height, neither a toe kick front nor a support frame is created. The **Toe kick** card groups toe height, timber thickness, upright timber height,
and the support-frame toggle. The front panel spans the full cabinet width.
Existing cabinets receive the new defaults when edited. Existing toe heights
below 100 mm need one of these adjustments before regeneration.

## Dimensions

All design inputs are in **millimetres**.

- **Width:** Overall case width.
- **Height:** Total height including the toe kick.
- **Depth:** Overall outside depth including the back and overlay fronts. Overlay front thickness is reserved within the input depth when a bay contains doors or drawers. All-open layouts reserve no front thickness.
- **Back panel:** Applied outside the case, within the requested depth. Case depth equals `depth - back thickness - overlay projection`.
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
ruby test/construction_test.rb
ruby test/stack_test.rb
ruby test/shallow_drawer_test.rb
ruby test/updater_test.rb
python3 scripts/update_manifest.py --check
bash scripts/build.sh
```

Output: `dist/Kero_Cabinet_v0.7.0.rbz`.

CI checks text, Ruby syntax, 27 geometry configurations, and archive integrity on pushes and pull requests. Successful runs upload the installation package.

## Existing models

From v0.4.1, the saved depth value includes the back panel. Editing and regenerating an older cabinet with the same depth shortens its case by the back thickness. To preserve its previous physical depth, increase the input by that thickness before regenerating.

Stored configuration keys and enum values remain compatible. Existing user-entered cabinet names are preserved; rename them in the editor if desired. Regenerating a cabinet replaces its generated parts with English names. Old unused component definitions or materials already stored in a SketchUp model are not purged.

## Limitations

- No hinge holes, runner models, or joinery details.
- Drawer boxes use simple rectangular panels.
- Not every dimension combination or manufacturing tolerance has been verified in SketchUp.
- Runtime UI and OpenCutList integration require manual testing in SketchUp.

## License

No license has been selected. No new license is added by this translation.

From v0.7.0, overlay front thickness is also included in the saved depth value. Regenerating an older overlay cabinet with the same input shortens the case by the front thickness. Increase the input by the front thickness only if you want to preserve the old physical depth.
