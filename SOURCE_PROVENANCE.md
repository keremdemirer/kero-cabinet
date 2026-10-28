# Source provenance

Retrieved original local downloads on 2026-10-28. Both plugin files in the source archive were byte-for-byte identical to the v0.2.2 RBZ before translation. No missing plugin implementation was recreated.

Original archive SHA-256 checksums:

- `Kero_Cabinet_v0.2.2.rbz`: `c1e8e0bdecc376b7cc6c5391497c422796c0bd61f6a463091881d0fe88343d6b`
- `kero-cabinet-github-source.zip`: `59edc1b247467c6319d99fb01558e72d41e71cf8f082f65e3644f152d934efb5`

The initial translated build retained version 0.2.2 and changed text only in the original plugin. Version 0.3.0 adds a new GitHub updater and update menu integration; the original geometry implementation remains unchanged. Documentation and a text regression guard are updated separately. Geometry tests use the original 16 scenarios with translated name lookups and Ruby 2.6-compatible test helper syntax.
