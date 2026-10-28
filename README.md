# Kero Cabinet

**A parametric cabinet builder for SketchUp.** Enter dimensions and a bay layout to create an editable cabinet component.

Version: **v0.12.0 (early development)**. The original project reports use in SketchUp 2025. Automated tests use a mock SketchUp API; they are not runtime integration tests.

## Features

- Width, height, depth, panel and back thickness, toe kick, and front gaps
- Full-height sides with top/bottom between them, or full-width top/bottom with sides between them
- Optional face frame and inset or overlay fronts
- 1-6 vertical bays with relative width weights
- Door, drawer (1-8 drawers), and open-shelf bays
- Separate named SketchUp instances sharing stock component definitions
- Edit existing cabinets using their saved parameters
- Full-width back panel applied outside the case
- English interface, validation errors, generated part/material names, documentation, and tests

The plugin does not generate cut lists. It targets **CutList v4.1.12** for the current workflow. Scale-aware measurement and sheet classification have been checked with that extension's original code using mock SketchUp geometry. Full SketchUp UI/PDF output still needs runtime verification. OpenCutList is a different extension and has not been validated for this shared-stock workflow.

## Installation

1. Download the RBZ from the `kero-cabinet-rbz` artifact of a successful GitHub Actions run, or build it locally.
2. In SketchUp, open **Extensions > Extension Manager > Install Extension**.
3. Select `Kero_Cabinet_v0.12.0.rbz` and restart SketchUp.
4. Choose **Extensions > Kero Cabinet > Create new cabinet...**.

To edit a cabinet, select its component and choose **Kero Cabinet | Edit parameters** from the context menu, or **Edit selected cabinet...** from the extension menu.

## Updates from GitHub

Install v0.12.0 once using the RBZ. Future releases can be installed from
**Extensions > Kero Cabinet > Check for updates...**, without downloading or
installing another RBZ manually. The plugin reloads automatically after an update. Apply or cancel any open cabinet
editor changes before starting: editors close during reload. The model is not
regenerated automatically.

The public `keremdemirer/kero-cabinet` repository requires no token or Git installation.
The plugin checks `main` in the background at startup and offers newer versions.
Disable startup checks under **Update settings...**. Startup network errors stay
quiet; manual checks display errors. Updates always require your confirmation.

Downloads use SketchUp native asynchronous HTTPS, one fixed repository revision,
and SHA-256 verification. Requests time out after 40 seconds. Ruby TLS is used
only outside the native SketchUp transport environment.
Only the three plugin Ruby files listed in `update.json` can be replaced.
Files are staged before replacement; handled installation failures restore the
previous files. Live reload preserves the module and existing menu callbacks. Do not close SketchUp while installation is in progress.
The plugin directory must be writable. Symlink installations are not supported.
The updater does not change existing cabinet geometry or save your open model.
If live reload fails, it reports the failure and requests a SketchUp restart.
Reload plugin now can also load locally installed files without a restart.
Extension Manager version metadata may remain stale until SketchUp restarts;
the cabinet editor and update checks use the active code version.

For each release, increase the version in both Ruby entry files, run
`python3 scripts/update_manifest.py`, test, and commit all files together.
Only version increases are offered; ordinary commits at the same version are
not installed automatically. This is a source updater for this unsigned extension;
it does not preserve Extension Warehouse signatures. Runtime testing in SketchUp
is still required. Future additional plugin assets require an updater migration.

Internal shelves behind inset doors start behind the door back with the configured gap. Their rear edges remain aligned with the case; open shelves keep their original depth.

### First upgrade to live reload

The updater running before v0.12.0 still asks for a restart. After installing this
version using the old updater or Extension Manager, apply/close Kero Cabinet
editors, then run this once in **Window > Ruby Console** to activate without a
SketchUp restart:

```ruby
load File.join(Sketchup.find_support_file('Plugins'), 'kero_cabinet/updater.rb'); KeroCabinet::Updater.reload_plugin
```

Future in-plugin updates reload automatically. **Reload plugin now...** is under
Kero Cabinet after a fresh launch, or appears as **Kero Cabinet | Reload plugin
now...** directly in Extensions for a live-upgraded session. Existing cabinet
geometry changes only when you edit and regenerate it. Live reload tests use a
mock SketchUp API; real runtime validation on the user's installation is needed.

### Update connection troubleshooting

Internet access in a browser does not prove that SketchUp can reach GitHub.
From v0.12.0 the updater uses SketchUp's native HTTP transport and reports the
actual failure category. Check application firewall/proxy/VPN settings when
SketchUp cannot reach `api.github.com`. Certificate checks are never disabled.
If an older updater cannot download this fix, install the current RBZ once via
Extension Manager and restart SketchUp before checking again. Native HTTP tests
use mocks; a runtime check on the affected SketchUp installation is still needed.

## Per-cabinet worktops

In the cabinet editor, enable **Worktop > Create worktop for this cabinet**.
Default stock is **30 mm MDF**, with zero overhangs. Material name, thickness,
and front/rear/left/right overhangs are independently editable. The option is
**off by default**, including older cabinets, to avoid duplicating existing tops.

The top is a part inside the cabinet assembly. Editing and regenerating the
cabinet recalculates its width, outside depth (including overlay fronts), and
position. Cabinet height remains the case height; worktop thickness is added
above it. Overhangs add outside the case/front footprint. It does not replace
the structural top panel. Neighboring cabinets should normally keep shared-side
overhangs at zero to avoid overlapping tops.

Equal material/thickness tops share a separate **30 mm MDF Worktop Sheet** stock
definition and material. CutList counts their instances with their actual sizes.
Disable the checkbox and regenerate to remove the integrated top. Existing
manually modeled or independent worktops are not automatically removed. The
shared-worktop command rejects selections already containing integrated tops.

## Independent worktops

Select one or more adjacent Kero Cabinet components at the same top height and
choose **Create worktop from selection...**. The command is under Kero Cabinet,
or directly in Extensions as **Kero Cabinet | Create worktop from selection...**
for a live-upgraded session without a retained submenu.

The worktop spans the complete selected run, including front projections. Set its
name, independent material name (default **MDF**), thickness (default **30 mm**),
and front/rear/left/right overhangs (default zero). It sits on the cabinet tops;
its thickness is additional to cabinet height. It is a separate scaled component,
using a stock/material name such as **30 mm MDF Worktop Sheet**, distinct from
ordinary **30 mm Sheet** stock and recognized by CutList's default Sheet words.

Select the resulting top and choose **Edit selected worktop...** to change these
settings. Cabinet geometry is unaffected. Existing manually modeled tops are not
removed or converted. The top stores its original footprint independently; if
cabinet dimensions/positions change, recreate the top from the new selection.

This first version supports straight runs of adjacent, unrotated, unscaled
components with matching top heights, depths and front/rear alignment. Different
heights (such as a lower center section) need separate worktops. Gaps, overlaps,
rotations and mixed depths are rejected rather than silently bridged. L-shaped
runs, automatic seams and maximum commercial sheet sizes are not implemented;
check available stock and divide long runs into suitable selected groups.

## Shared stock components and CutList v4.1.12

Every stock thickness/type has one owned component definition and one material:
for example **18 mm Sheet**, **12 mm Sheet**, **6 mm Sheet**, and
**50 x 100 mm Timber**. Parts are scaled instances of these definitions. Parts
of equal sheet thickness share stock regardless of their cabinet role; this
assumes they are the same real material. Separate species/finish choices are
not yet implemented. Face-frame members are grouped as dimensional timber.

Instance names and `kero_cabinet/part_name` attributes retain Left side, Shelf,
Drawer bottom and other part identities in the model. CutList 4.1.12 uses the
**definition name** for its Description column, so its descriptions show the
stock name, not the per-instance part role. Its material column also shows the
stock name. Dimensions and quantities still distinguish different pieces.

The default Sheet Material Words contain `sheet`, so these parts classify as
Sheet Goods; Timber has no sheet keyword and remains in the board group. Keep
Layout by Material enabled and choose actual sheet sizes under Sheets. With
By Sub-Assembly, separate cabinets retain their assembly groupings. Compact
combines matching stock-name/dimension/material items according to CutList rules.

Editing regenerates the cabinet and removes only unused former part definitions
from that cabinet. Shared definitions still used by any instance are retained.
No global purge runs; unrelated definitions and materials are not deleted.
Older unused KC definitions left by earlier editing sessions are not globally
purged. Existing cabinets migrate only when edited and regenerated.

Do not manually edit a stock definition: all its instances share its geometry.
Use Kero Cabinet parameters. Scaling preserves the original part bounds, but no
new manufacturing operations, grain rules or machining details are added.

Optional test against a locally installed CutList, without modifying it:

```bash
CUTLIST_PLUGIN_DIR="/path/to/SketchUp/Plugins/sr_cutlist" ruby test/cutlist_integration_test.rb
```

This loads the original parts measurement implementation and extracts the original
classification method; it does not automate CutList's full UI/export pipeline.

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

### Drawer box height

**Drawer construction > Drawer box height** applies to all drawers:

- **Fit available height** (default): use the available front/cavity height after
  hardware clearances; there is no fixed 125 mm cap.
- **Limit height**: cap box height at **Maximum box height**, initially 125 mm.
  Smaller openings still shrink the box to fit. A cap below the hardware/stock
  minimum is rejected with an explanatory error.

Visible fronts, width, depth, slide selection and bottom recess stay unchanged.
Existing cabinets without these settings use Fit when edited and regenerated;
select Limit / 125 mm to preserve their previous short-box height behavior.

### Shallow drawers and side-mount slide profiles

Choose **Drawer hardware** under Drawer construction. The default Easy-close
profile uses a 47.7 mm minimum box height and 13.5 mm side clearance (3832EC
reference). Low-profile uses a 35.1 mm minimum box height and 13.0 mm side
clearance (2132C reference). These rounded minimum heights come from manufacturer
minimum drawer-height requirements, not merely slide-body dimensions.

The old fixed 100 mm section / 85 mm front / 60 mm box limits no longer apply
to drawers. Box height fills available space by default. Optional Limit height caps it at a
selected maximum (125 mm initially). Kero Cabinet reserves 4 mm above and below the box and at least
10 mm usable above its bottom. These are application allowances, not manufacturer
specifications. Sections still need room for front/frame margins and dividers.
Errors report the available front/opening and required height.

Profiles cover minimum height and side space only. They do not certify hardware
compatibility: slide length increments, maximum width, loads, mounting brackets,
setbacks, fasteners and holes must follow the exact product data. Undermount uses the separate TANDEM reference described below. See [Hardware references](HARDWARE.md).

### Undermount hardware

Select **Drawer hardware > Undermount - Blum TANDEM 563H reference**. Side-mount
profiles remain in their own option group. Existing models retain their selected
side-mount profile unless changed.

- Supported side stock: **12-16 mm** (16 mm manufacturer maximum; 12 mm is the
  lower bound supported by this reference implementation).
- Inner box width: **runner opening width minus 42 mm**. Outer width adds twice
  the selected side thickness. In face-frame cabinets, use the clear face-frame
  opening; mounting blocks/brackets still need separate design.
- Bottom recess: **13 mm**. Front/back box members are raised by the same amount,
  leaving the underside open. This is simplified stock geometry, not exact
  manufacturer rear-notch machining.
- Reserve **14 mm below and 6 mm above** the box. Minimum box height is computed
  as recess + bottom thickness + 10 mm usable interior; it is a plugin allowance,
  not a published minimum drawer height.
- Drawer length choices: **229, 305, 381, 457, 533 mm**, default **Auto - longest fitting**. Saved manual choices remain fixed. Check enough
  depth remains behind the placed box front: length + 24 mm, or +37 mm for 229.
  This is a conservative depth fit check; bracket ranges require product review.

This profile is based on the [Blum 563H/563 installation sheet](https://d2.blum.com/services/BEC003/tdm563h_ma_dok_bus_%24sen-us_%24aof_%24v4.pdf).
Hook holes, locking devices, exact rear notches, grooves, runner models and drilling
are **not generated**. Prepare them with the manufacturer template before making
a production drawer. The generated box is not a complete hardware-ready cut plan.

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
ruby test/undermount_test.rb
ruby test/drawer_height_test.rb
ruby test/reload_test.rb
ruby test/stock_test.rb
ruby test/worktop_test.rb
ruby test/updater_test.rb
python3 scripts/update_manifest.py --check
bash scripts/build.sh
```

Output: `dist/Kero_Cabinet_v0.12.0.rbz`.

CI checks text, Ruby syntax, 27 geometry configurations, and archive integrity on pushes and pull requests. Successful runs upload the installation package.

## Existing models

From v0.12.0, regenerating a cabinet replaces per-part definitions with shared
stock definitions and applies stock-based material names.

From v0.4.1, the saved depth value includes the back panel. Editing and regenerating an older cabinet with the same depth shortens its case by the back thickness. To preserve its previous physical depth, increase the input by that thickness before regenerating.

Stored configuration keys and enum values remain compatible. Existing user-entered cabinet names are preserved; rename them in the editor if desired. Regenerating a cabinet replaces its generated parts with English names. Old unused component definitions or materials already stored in a SketchUp model are not purged.

## Limitations

- No hinge holes, runner models, or joinery details.
- Drawer boxes use simple rectangular panels.
- Not every dimension combination or manufacturing tolerance has been verified in SketchUp.
- Runtime UI and full CutList export require manual testing in SketchUp. OpenCutList has not been validated.

## License

No license has been selected. No new license is added by this translation.

From v0.12.0, overlay front thickness is also included in the saved depth value. Regenerating an older overlay cabinet with the same input shortens the case by the front thickness. Increase the input by the front thickness only if you want to preserve the old physical depth.

### Drawer depth fitting (v0.12.0)

Undermount Auto selects the longest supported nominal length fitting the available
space, retaining required rear allowance. Supported lengths currently stop at
533 mm; a deeper cabinet can therefore retain unused space. Select Auto on older
cabinets whose saved length is fixed at 457 mm or another manual value.
Side-mount boxes use available depth minus the adjustable Side-mount rear
clearance (3-50 mm, default 10). Front setback now reserves the actual front and
mounting clearance rather than an unconditional extra 18 mm. Exact commercial
slide lengths, brackets and mounting details still need product-specific review.

Overlay stacked sections use the same gap-centered front grid as uniform drawer banks. With matching cabinet height, toe height, and gap, a bottom section weighted 1 of a total 4 aligns with the bottom front of four equal drawers. Inset sections retain divider/face-frame allowances and do not guarantee the same front-edge alignment.
