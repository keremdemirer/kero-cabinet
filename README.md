# Kero Cabinet

**A parametric cabinet builder for SketchUp.** Enter dimensions and a bay layout to create an editable cabinet component.

Version: **v0.19.0 (early development)**. The original project reports use in SketchUp 2025. Automated tests use a mock SketchUp API; they are not runtime integration tests.

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

The plugin includes a simple native cut list: use **Cut list from selection...** or **Cut list from all Kero objects...** in its menu. Both include only Kero-owned wood parts and independent worktops, merge matching material and blank sizes, and offer CSV and printing. The Print button opens a browser print view; use Print / Save as PDF there. Hardware is excluded; hidden parts are included. Selected groups are searched recursively. Each placed instance is counted, including linked copies. Sizes use actual geometry and parent scales; skewed geometry is rejected. This report does not include edge banding, grain direction or sheet nesting. Reports are snapshots; reopen after editing the model.

For advanced output, It targets **CutList v4.1.12** for the current workflow. Scale-aware measurement and sheet classification have been checked with that extension's original code using mock SketchUp geometry. Full SketchUp UI/PDF output still needs runtime verification. OpenCutList is a different extension and has not been validated for this shared-stock workflow.

## Installation

1. Download the RBZ from the `kero-cabinet-rbz` artifact of a successful GitHub Actions run, or build it locally.
2. In SketchUp, open **Extensions > Extension Manager > Install Extension**.
3. Select `Kero_Cabinet_v0.19.0.rbz` and restart SketchUp.
4. Choose **Extensions > Kero Cabinet > Create new cabinet...**.

To edit a cabinet, select its component and choose **Kero Cabinet | Edit parameters** from the context menu, or **Edit selected cabinet...** from the extension menu.

## Updates from GitHub

Install v0.19.0 once using the RBZ. Future releases can be installed from
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

The updater running before v0.9.0 still asks for a restart. After installing this
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
From v0.6.1 the updater uses SketchUp's native HTTP transport and reports the
actual failure category. Check application firewall/proxy/VPN settings when
SketchUp cannot reach `api.github.com`. Certificate checks are never disabled.
If an older updater cannot download this fix, install the current RBZ once via
Extension Manager and restart SketchUp before checking again. Native HTTP tests
use mocks; a runtime check on the affected SketchUp installation is still needed.

## Linked cabinet copies

Select a Kero Cabinet and choose **Create linked copy** from its context menu or
Kero Cabinet menu. A new copy is placed beside it with a 100 mm separation.
It shares the original cabinet definition. Editing either cabinet through the
plugin and choosing Apply to model regenerates the whole linked family,
including its integrated worktop, material settings and internal layout.
Each instance keeps its own placement/transform. Copies do not automatically
move apart when the cabinet width changes; reposition them as needed.

The editor shows the linked-family count. Stored settings are read from the
shared definition and refreshed on all family instances after applying. Reopen
other open editors after changing a linked family to avoid applying stale values.
Standalone worktops are separate objects and do not follow linked edits.

Choose **Make independent** to detach only the selected cabinet. Existing ordinary
copies are isolated before starting a new linked family and continue to edit
independently. Linked status is stored in the model and survives reopen/reload.
Native SketchUp copies of an already-linked cabinet also share that family unless
made independent. Material stock definitions remain shared even after a cabinet
is made independent; its cabinet parameters and assembly geometry are separate.

## Cabinet editor

The editor is organized into five tabs:

- **Size & fronts**: cabinet name, overall dimensions, inset/overlay placement,
  and face-frame enablement. Frame dimensions are under an expandable detail.
- **Layout**: left-to-right bays and mixed drawer/door/shelf sections.
- **Build**: material thicknesses, top/bottom/back construction, and drawer hardware.
- **Base**: No base, Timber toe kick, or Casters and the selected support settings.
- **Worktop**: optional per-cabinet worktop, thickness, material, and overhangs.

Worktop fields remain hidden until enabled; timber dimensions hide when supports
are off or toe height is zero. Long explanations and top-panel placement diagrams
are expandable. A persistent footer shows dimensions, bay count and front style.
Invalid numeric inputs automatically reveal their tab/details and receive focus.
Tabs support keyboard arrows and Home/End. All existing saved parameters are
preserved; existing cabinets default to Timber toe kick.

Grouping references: [CabinetSense cabinet properties](https://sites.google.com/a/cabinetsensesoftware.com/cabinetsense-wiki/component-glossary/base-cabinet)
and [SketchThis feature help](https://app.sketchthis.net/help/). No third-party
code, branding, icons or proprietary visual assets are copied. The editor is
custom to Kero Cabinet.

## Per-cabinet worktops

In the cabinet editor, enable **Worktop > Create worktop for this cabinet**.
Default stock is **30 mm MDF**, with zero overhangs. Material name, thickness,
and front/rear/left/right overhangs are independently editable. The option is
**off by default**, including older cabinets, to avoid duplicating existing tops.

The top is a part inside the cabinet assembly. Editing and regenerating the
cabinet recalculates its width, outside depth (including overlay fronts), and
position. Overall height includes the enabled worktop. Case height equals Overall height
minus worktop thickness, and the worktop upper face stays at Overall height. Overhangs add outside the case/front footprint. It does not replace
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
its thickness is additional to the selected run height because this is a separate worktop command. Integrated per-cabinet tops are instead included in Overall height. It is a separate scaled component,
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

## Migrate a model after an update

After installing a new version, close Kero Cabinet panels, exit component/group
editing and choose **Kero Cabinet > Migrate all to current version...**. This is
an explicit command; updating plugin files does not regenerate the model automatically.
The command reports the number of cabinet instances and independent worktops before
starting. It includes objects inside nested groups/components, even when hidden.
Shared container definitions are scanned once; unused definitions are not targets.

All saved configurations and generated layouts are checked before changing the
model. Invalid settings, unsupported independent-worktop stock or locked targets
(including locked containers) stop the whole migration with an object-specific
message. Unlock or correct the reported objects, then retry.

Cabinets are regenerated from their saved parameters. Each linked family is
rebuilt once; ordinary copies retain independent parameters. Placement transforms,
opening poses and selection are preserved. Independent worktops retain their
instance placement, tags, visibility and scale while refreshing their stock and
version. Integrated worktops and organizers regenerate with their cabinet.
New geometry rules can change part dimensions even when input parameters stay
the same. Manually edited generated parts are replaced, just as with Apply to model.

The migration is one SketchUp undo operation. A runtime failure aborts the complete
operation rather than leaving a partially updated batch. Automated tests verify
operation boundaries and abort handling with mocks; native undo/rollback still
requires runtime validation in SketchUp. There is no global purge.

The same command can be invoked from **Window > Ruby Console**:

```ruby
KeroCabinet.migrate_all_command
```

## Interior inspection

Select a cabinet and open **Kero Cabinet > Interior view...**, the matching
right-click command, or **Interior view...** in its parameter editor. Apply pending
parameter edits first; the live panel uses the saved cabinet layout.
Each door section and individual drawer has an **Open** switch.

Drawers slide forward as one assembly: applied front, box, divider panels and
Gridfinity previews move together. Preview travel is 90% of the actual box depth.
Doors swing outward by 90 degrees about their outer rear hinge edges; a single
leaf is left-hinged and paired leaves open from opposite edges. Fronts remain
visible. This is an open/closed pose, not an animation, commercial hinge model or
hardware stroke/collision simulation. Inspect neighboring clearances separately.

**Open all** and **Close all** operate on the selected cabinet. Closing restores
saved closed transforms exactly; repeated toggles do not accumulate movement.
Changes are undoable, persist in the model and survive regeneration. Targets follow
bay, section and drawer positions. Linked copies share the pose; ordinary copies
are isolated when changing it. Old hidden-front states migrate to opening poses
when the panel is next used. The panel closes during plugin reload.

Close all before measuring overall cabinet bounds, creating a worktop from a
selection or exporting a closed assembly. Opening changes part placement, not
stock dimensions; no front geometry is hidden or deleted by the new opening mode.

## Drawer organizers

Under **Layout > Drawer organizers**, choose an organizer independently for each
drawer. Drawer 1 is the bottom drawer. **Apply to all drawers in this section**
copies the current settings; later edits remain independent. Mixed-layout drawer
sections support the same controls. Existing cabinets default to no organizers.
Linked cabinet families share organizer settings along with their other parameters.

**Panel dividers** support Front-to-back, Side-to-side and Grid layouts. Default
stock is 6 mm Plywood, independent of drawer-box stock. Ratios such as `1 2 1`
describe clear compartment sizes after reserving divider thickness. Each axis
accepts 1-12 ratios. Default perimeter clearance is 1 mm per edge. Height `0`
automatically leaves 10 mm above the dividers; a positive height sets a custom
value and must leave at least 2 mm above. Dividers rest on the actual inside
bottom surface, including an undermount bottom recess, and do not cut channels
into the drawer. Grid dividers have complementary half-height notches at nominal
stock thickness. Fit the slots to the measured sheet before fabrication; no
extra machining tolerance is added. CutList measures the full blank dimensions,
not the notch paths, using material names such as **6 mm Plywood Sheet**.
Identical divider profiles share definitions; different notch layouts require
separate profiles even when their sheet material is the same.

**Gridfinity** is a layout planner using a 42 mm grid. It fits complete cells into
the real drawer interior after edge clearance and supports Center or Front left
alignment. **Update fit preview** reports cell counts, interior dimensions,
left/right/front/back edge gaps and maximum bin height units. Add bins with a
column, row, width/depth in cells and height in 7 mm units. Column 1 / row 1 is
front left. Out-of-grid, overlapping and over-height bins are rejected.
The top view labels each bin and shows the front at the top. Cabinet generation
creates a baseplate envelope, grid lines and hollow bin envelopes for planning.
Edge gaps are reported; printable fillers are not generated in this release.

Gridfinity previews use `42n - 0.5 mm` bin footprints, a 3.8 mm lip allowance and
a conservative, fully additive 5 mm baseplate allowance for height checks.
Actual mating feet nest into sockets, so the preview is not an exact assembled
product height. There are no mating profiles, magnets, screw holes, stacking
features or printable STL exports. Select a real baseplate/bin profile and check
its fit separately. Preview components/material are **Gridfinity Preview Hardware**,
so CutList classifies them as hardware instead of wood or sheet goods.
The grid reference is the [community Gridfinity specification](https://github.com/gridfinity-unofficial/specification).

Fit preview runs the same layout calculations as model generation without changing
the model. Refresh it after changing dimensions, stock, hardware or organizer settings.

## Base options

Choose **Base > Base type**:

- **No base**: no toe kick fascia, timber or casters; the bottom panel starts at floor level.
- **Timber toe kick**: existing toe kick and optional support frame; this remains the default.
- **Casters**: four representative corner casters replace the fascia and timber frame.

Overall height includes the selected base and any enabled worktop. Changing base type
keeps the overall height and adjusts the available case height. Settings for inactive
base types are retained so switching back restores their previous values.

Caster defaults are 100 mm mounting height, 75 mm wheel diameter, 30 mm plate-edge
inset and brakes on the front two casters. Mounting height means plate-to-floor;
it is separate from wheel diameter. Plates sit under the bottom panel. Oversized
plates/insets that cannot fit are rejected. The geometry is representative, with
76 mm minimum plate length and 60 mm plate width; it does not generate manufacturer
holes, swivel motion or a certified support layout. Confirm actual product dimensions,
load capacity and bottom-panel mounting strength before fabrication. Additional
casters for large or heavily loaded cabinets are not generated automatically.

Caster components and material are named **Caster Hardware**, allowing CutList's
default hardware keyword to classify them separately from wood and sheet goods.

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
- **Height:** Total height including the selected base and enabled worktop.
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
ruby test/drawer_front_test.rb
ruby test/interior_view_test.rb
ruby test/migration_test.rb
ruby test/native_cutlist_test.rb
ruby test/reload_test.rb
ruby test/stock_test.rb
ruby test/worktop_test.rb
ruby test/base_test.rb
ruby test/organizer_test.rb
ruby test/linked_copy_test.rb
node test/editor_test.js
ruby test/updater_test.rb
python3 scripts/update_manifest.py --check
bash scripts/build.sh
```

Output: `dist/Kero_Cabinet_v0.19.0.rbz`.

CI checks text, Ruby syntax, 27 geometry configurations, and archive integrity on pushes and pull requests. Successful runs upload the installation package.

## Existing models

From v0.10.0, regenerating a cabinet replaces per-part definitions with shared
stock definitions and applies stock-based material names.

From v0.4.1, the saved depth value includes the back panel. Editing and regenerating an older cabinet with the same depth shortens its case by the back thickness. To preserve its previous physical depth, increase the input by that thickness before regenerating.

Stored configuration keys and enum values remain compatible. Existing user-entered cabinet names are preserved; rename them in the editor if desired. Regenerating a cabinet replaces its generated parts with English names. Old unused component definitions or materials already stored in a SketchUp model are not purged.

## Limitations

- No hinge holes or runner machining. Organizer half-lap profiles are modeled; other manufacturing joinery is not generated.
- Drawer boxes use simple rectangular panels.
- Not every dimension combination or manufacturing tolerance has been verified in SketchUp.
- Runtime UI and full CutList export require manual testing in SketchUp. OpenCutList has not been validated.

## License

No license has been selected. No new license is added by this translation.

From v0.6.4, overlay front thickness is also included in the saved depth value. Regenerating an older overlay cabinet with the same input shortens the case by the front thickness. Increase the input by the front thickness only if you want to preserve the old physical depth.

### Drawer depth fitting (v0.8.1)

Undermount Auto selects the longest supported nominal length fitting the available
space, retaining required rear allowance. Supported lengths currently stop at
533 mm; a deeper cabinet can therefore retain unused space. Select Auto on older
cabinets whose saved length is fixed at 457 mm or another manual value.
Side-mount boxes use available depth minus the adjustable Side-mount rear
clearance (3-50 mm, default 10). The drawer box starts directly against the back
of its applied front in both inset and overlay configurations. Face-frame boxes
use the narrower of the frame and case openings for both runner families, preventing frame collisions
when the box reaches forward. Existing face-frame side-mount boxes may become
narrower when regenerated; boxes also clear horizontal frame rails vertically.
Organizers are recalculated from the new interior. Exact commercial
slide lengths, brackets and mounting details still need product-specific review.

Overlay stacked sections use the same gap-centered front grid as uniform drawer banks. With matching cabinet height, toe height, and gap, a bottom section weighted 1 of a total 4 aligns with the bottom front of four equal drawers. Inset sections retain divider/face-frame allowances and do not guarantee the same front-edge alignment.

From v0.12.1, regenerating a cabinet with its integrated worktop enabled includes that top within the saved Overall height. To preserve the taller physical height generated by v0.12.0, increase the saved height by the worktop thickness before regeneration. Independent worktops are unchanged.
