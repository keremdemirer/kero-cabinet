# Changelog

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
