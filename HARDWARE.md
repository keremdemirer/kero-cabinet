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
validation. Undermount slide systems require different construction and are not
supported by these profiles.
