# Changelog

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
