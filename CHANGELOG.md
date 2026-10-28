# Changelog

## v0.17.0 - 2026-10-29
- Add a live Interior view panel with per-door-section and per-drawer Show interior switches.
- Hide selected fronts without moving or deleting geometry; include Show all interiors and Show all fronts actions.
- Preserve view state through regeneration, share it within linked families and isolate ordinary copies.
- Expose the panel in the menu, context menu and cabinet editor, with undoable model changes and reload cleanup.
- Document saved-layout behavior and restoring fronts before exports that omit hidden objects.

## v0.16.1 - 2026-10-29
- Seat every drawer box directly against the rear face of its applied drawer front.
- Remove artificial front gaps and face-frame depth setbacks for side-mount and undermount drawers, including inset and overlay layouts.
- Size both runner families from the clear face-frame opening so forward boxes clear the stiles and horizontal frame rails.
- Recalculate drawer depths and organizers while preserving rear hardware allowances and nominal undermount lengths.
- Verify mating faces, frame clearance, stacked drawers and organizer bounds across frame/front/hardware combinations.

## v0.16.0 - 2026-10-29
- Add independent per-drawer None, Panel dividers and Gridfinity organizers, including stacked sections and linked cabinets.
- Generate removable sheet dividers with weighted compartments, independent stock/height and complementary half-lap grid profiles.
- Plan 42 mm Gridfinity layouts and bins using actual interior dimensions, with alignment, edge-gap reporting and collision/height checks.
- Add model-free fit previews, top views and copy-to-section controls; reject stale preview responses.
- Keep Gridfinity envelopes separate from sheet goods using Hardware classification; no printable mating profiles or STL export.
- Verify organizer geometry, hardware/stock combinations, CutList measurements and editor serialization.

## v0.15.0 - 2026-10-29
- Split Base and Worktop into separate editor tabs.
- Add No base, Timber toe kick and Casters base modes, preserving legacy timber defaults.
- Include the selected base and optional worktop within overall height.
- Add four representative casters with mounting height, wheel diameter, plate inset and front-brake settings.
- Classify caster components as Hardware and verify geometry, linked edits, editor serialization and CutList classification.

## v0.14.0 - 2026-10-29
- Add Create linked copy and Make independent commands with context-menu support.
- Regenerate linked cabinet families from either instance while preserving placement transforms.
- Store shared configuration on the family definition and refresh instance metadata after edits.
- Show a linked-family disclosure in the editor and verify isolation from ordinary copies and detachment.

## v0.13.0 - 2026-10-29
- Reorganize the editor into Size & fronts, Layout, Build, and Base & top tabs.
- Add a persistent dimensions/layout summary, progressive details, conditional worktop/timber fields, and a simpler Apply to model action.
- Reveal hidden invalid fields automatically and support keyboard tab navigation.
- Preserve all saved defaults and verify editor navigation, validation, serialization and layout summaries.

## v0.12.1 - 2026-10-28
- Include integrated worktop thickness within Overall height.
- Shorten case panels, backs, dividers, fronts and interior layouts consistently, and validate available case height after the deduction.
- Preserve independent-worktop behavior and test multiple top thicknesses/construction modes.

## v0.12.0 - 2026-10-28
- Add optional per-cabinet worktops with 30 mm MDF defaults and separate material/thickness/overhang controls.
- Regenerate integrated tops with their cabinet dimensions and preserve shared Worktop Sheet stock definitions.
- Default to disabled on existing cabinets and prevent shared-worktop creation over already integrated tops.
- Verify integrated size changes, overlay depth, material reuse and removal when disabled.

## v0.11.0 - 2026-10-28
- Create independent worktops from adjacent same-height cabinet selections, with 30 mm default thickness, separate material naming and four overhang settings.
- Edit worktop settings without changing the cabinets and reuse separate Worktop Sheet stock definitions.
- Reject mixed-height/depth, rotated, gapped and overlapping runs.
- Verify worktop geometry, stock reuse and original CutList measurement/classification.

## v0.10.0 - 2026-10-28
- Share owned stock component definitions across scaled part instances and cabinets, with thickness-based Sheet materials and dimensional Timber materials.
- Preserve per-instance role names and real geometry, and classify sheets using default CutList material words.
- Remove only unused candidate definitions from an edited cabinet, retaining shared or unrelated definitions.
- Verify geometry regressions and integrate against original installed CutList v4.1.12 measurement/classification code.
- Document stock-name descriptions in CutList and the remaining full-UI export verification step.

## v0.9.0 - 2026-10-28
- Reload installed plugin code automatically after updates without restarting SketchUp.
- Close cabinet editors with update consent, preserve live module/menu callbacks, and avoid duplicate menu registration.
- Add a manual reload command, first-upgrade console activation, and explicit restart fallback on reload failure.
- Verify repeat reloads, unchanged mock model state, old-core transition and failure reporting.

## v0.8.4 - 2026-10-28
- Use a shared gap-centered front grid for overlay stacked section boundaries and uniform drawer fronts.
- Align a 1:3 bottom drawer/upper door layout with the bottom of a four-drawer bank.
- Preserve inset divider allowances and test overlay alignment across frame, back, bottom and gap settings.

## v0.8.3 - 2026-10-28
- Clip each drawer box to its own front interval and section cavity before applying hardware clearances.
- Prevent overlay boxes from shifting into adjacent drawers when Fit available height is selected.
- Verify per-drawer intervals and separation for 2/4 drawers, both height modes, frame choices and three hardware profiles.

## v0.8.2 - 2026-10-28
- Add Fit available height (default) and Limit height drawer box modes with a configurable cap, initially 125 mm.
- Preserve front dimensions and hardware clearances while allowing taller boxes.
- Reject limits below hardware/stock minimums and verify both modes with side-mount/undermount, inset/overlay and face-frame combinations.

## v0.8.1 - 2026-10-28
- Add Auto - longest fitting nominal undermount length while preserving saved manual lengths.
- Replace fixed side-mount rear allowance with adjustable 3-50 mm clearance, default 10 mm.
- Remove unnecessary fixed front setback and preserve required front clearance.
- Test longest-fit selection, manual overrides and rear-clearance dimensions.

## v0.8.0 - 2026-10-28
- Separate side-mount and undermount hardware choices and add a Blum TANDEM 563H geometry reference.
- Compute inner box width from opening minus 42 mm, recess the bottom 13 mm, and reserve 14/6 mm lower/upper clearance.
- Support 12-16 mm sides and selectable nominal drawer lengths with depth validation.
- Document that hook bores, exact notches, grooves and locking hardware are not generated.
- Verify geometry across face-frame choices, stock thicknesses and five nominal drawer lengths.

## v0.7.0 - 2026-10-28
- Replace fixed drawer height limits with selectable side-mount height/side-space profiles referenced to Accuride 2132C and 3832EC.
- Adapt shallow box height to front and cavity space, retaining clearance and bottom-stock checks.
- Add available/required height diagnostics and document manufacturer figures separately from plugin allowances.
- Test sub-60 mm boxes, differing profile minimums, stacked shallow drawers, and invalid hardware choices.

## v0.6.4 - 2026-10-28
- Include overlay fronts within the requested overall depth and shorten the case, internal parts, and toe frame consistently.
- Reserve no front thickness for all-open layouts, including open-only stacked sections.
- Clarify the Overall depth label and verify bounding-box depth across front thicknesses and back modes.

## v0.6.3 - 2026-10-28
- Simplify the cabinet layout editor with direct content buttons, compact section controls, and a schematic preview.
- Show normalized height and width percentages alongside relative ratios.
- Add Drawer + doors, Equal split, and 3 sections presets; hide width ratios for a single bay.
- Disable unavailable removal/movement controls and keep sections visually ordered top to bottom.

## v0.6.2 - 2026-10-28
- Display stacked sections top to bottom to match their physical cabinet positions.
- Move Add section above above the section list, preserving saved geometry order and movement controls.

## v0.6.1 - 2026-10-28
- Dispatch updater downloads through SketchUp native asynchronous HTTP on the UI thread, avoiding reliance on embedded Ruby TLS configuration.
- Retain request objects, time out stalled requests, and ignore late callbacks after completion.
- Report actual SSL, DNS, timeout, HTTP, and invalid-response errors instead of one generic connection message.
- Add mocked native transport and worker/timer integration tests.

## v0.6.0 - 2026-10-28
- Add 2-6 bottom-to-top horizontal sections inside each vertical bay, mixing drawers, doors, and shelves with height weights and reorder controls.
- Generate horizontal divider panels and optional face-frame rails, with section-specific drawer and shelf bounds.
- Add clear numeric field names, submitted values in errors, front-end range/empty checks, and mouse-wheel protection.
- Cover stacked construction combinations, independent neighboring bays, invalid sections, and the reported numeric input values.

## v0.5.1 - 2026-10-28
- Add independent Between sides / Full width bottom construction, including with top/back support rails.
- Raise side-panel starts onto a full-width bottom without changing total height.
- Group top, bottom, and back settings in one card and preserve legacy bottom arrangements.
- Verify 32 combinations of top, back, bottom, panel arrangement, and face-frame settings.

## v0.5.0 - 2026-10-28
- Add independent full-panel/support-rail options for the top and back, with 100 mm rails using case material and thickness.
- Force full-height sides for rail construction and join upper rear rails without overlap.
- Preserve requested depth with internal back rails and retain the solid bottom.
- Add separate drawer box and bottom thickness settings, both defaulting to 12 mm.
- Preserve drawer outer sizes and runner clearances, and cover construction combinations and stock changes in regression tests.

## v0.4.2 - 2026-10-28
- Extend the toe kick front across the full cabinet width to cover the support frame ends.
- Group toe kick height and timber support-frame settings in one Toe kick card.
- Verify full-width coverage and floor-to-case panel height across geometry scenarios.

## v0.4.1 - 2026-10-28
- Include the externally applied back panel within the requested overall depth.
- Shorten case panels, shelves, drawer boxes, and the toe frame accordingly.
- Clarify the depth label and document changed depth semantics for existing cabinets.
- Check overall depth with 3, 6, and 24 mm backs across 27 geometry configurations.

## v0.4.0 - 2026-10-28
- Add a toe kick timber support frame, enabled by default with 50 x 100 mm stock, 100 mm upright.
- Use butt-jointed perimeter and cross rails behind the toe kick front, plus legs for taller toe spaces.
- Add adjustable stock dimensions and a support-frame toggle, and merge defaults when editing older cabinets.
- Verify butt joints, non-overlap, floor contact, and disabled/zero-height cases across 25 geometry configurations.

## v0.3.1 - 2026-10-28
- Recess shelves behind inset doors by the front thickness plus the configured gap.
- Keep shelf rear edges aligned with the case and preserve open-shelf depth.
- Cover frameless and face-frame cases, including thick inset doors, in 20 geometry configurations.

## v0.3.0 - 2026-10-28
- Add public GitHub update checks, startup preferences, verified downloads, and in-place installation with rollback on handled failures.
- Add updater regression tests and a release manifest checked by CI.
- Require a restart after updates; no repeated manual RBZ installation is needed.

## English translation
- Translate all repository documentation, plugin labels, settings, menus, validation errors, and generated part/material names into English.
- Translate geometry test lookups and add an English text regression guard.
- Expand test helper method syntax for compatibility with Ruby 2.6.
- Preserve v0.2.2 geometry, saved parameter keys, and enum values.

## v0.2.2 - 2026-10-28
- Apply the full-width back panel outside the rear of the case.
- Align top, bottom, and shelf rear edges with the side panels.
- Adjust drawer box depth for the external back panel.

## v0.2.1 - 2026-10-28
- Fix downward extrusion caused by reversed ground-plane face normals.

## v0.2.0 - 2026-10-28
- Add full-height side and full-width top/bottom construction options.
- Generate individual parts as separate SketchUp components.
- Focus on OpenCutList use instead of built-in cut list generation.

## v0.1.0
- Introduce parametric casework, bays, doors, drawers, face frames, and a SketchUp HtmlDialog interface.
