# Drawer slide references

Reviewed 2026-10-28 against manufacturer technical sheets.

| Profile | Reference | Manufacturer minimum drawer height | Implemented minimum box height | Side clearance per side |
| --- | --- | --- | --- | --- |
| Low-profile side mount | Accuride 2132C | 1.38 inches (35.052 mm) | 35.1 mm | 13.0 mm |
| Easy-close side mount | Accuride 3832EC | 1-7/8 inches (47.625 mm) | 47.7 mm | 13.5 mm |

Sources:

- [Accuride 2132C technical sheet](https://www.accuride.com/media/amasty/amfile/attach/450078e2404507b4075d06bcfead6ea6.pdf)
- [Accuride 3832EC technical sheet](https://www.accuride.com/media/amasty/amfile/attach/d4ba99d10b86f194bef3fdc51f9ccb24.pdf)

Both sheets give side space of 12.7 mm +0.8/-0.0 per side. The selected 13.0 mm
for 2132C is within that range. The 3832EC sheet recommends a drawer 27.0 mm
narrower than the cabinet opening, implemented as 13.5 mm each side.

The minimums are rounded upward. Four millimetres of box clearance above and
below, at least ten millimetres of usable interior above the bottom, and a
preferred box height of 125 mm are plugin design allowances, not product claims.
The generated geometry does not model actual slide assemblies or mounting holes.

These are height/side-space references, not certified product presets. In
particular, the 2132 catalog lists a 406 mm drawer-width limit; it is not enforced
by this height profile. Drawer width, available stock lengths, depth, mounting
setback, face-frame brackets, load capacity, and fastening details require review
against the exact slide variant. Do not infer suitability from passing geometry
validation. Undermount slide systems use a separate geometry reference below.

## Undermount: Blum TANDEM 563H/563 reference

[Manufacturer installation sheet](https://d2.blum.com/services/BEC003/tdm563h_ma_dok_bus_%24sen-us_%24aof_%24v4.pdf), pages 2-3:
inside width = opening minus 42 mm; maximum side thickness 16 mm; bottom recess
13 mm; lower clearance 14 mm; upper clearance 6 mm; maximum drawer height is
opening minus 20 mm. The implementation supports 12-16 mm sides and uses the
clear face-frame opening where present.

Nominal drawer lengths in this sheet are 229, 305, 381, 457, and 533 mm. Minimum
cabinet depths are 266, 328, 404, 480, and 557 mm respectively. The plugin applies
a conservative length +24 mm check behind the placed box front (+37 for 229),
while actual bracket installation ranges still require review.

The minimum generated box height is recess + bottom stock +10 mm usable interior,
a plugin construction allowance rather than a manufacturer minimum. Front/back
members are raised to leave the underside open; this does not generate the
specified 35 mm rear notches, 6 mm hook bores, angled locking-device holes,
grooves, brackets, or the physical runners. This geometry is not a complete
production drawer or certified hardware compatibility check.
