---
"better-supabase": minor
---

`maintenance` plans take calendar rules and required qualifications.

- A plan of kind `rrule` takes an RFC 5545 `rrule`, a `dtstart` and a `tz`, next to the `time` and `meter` kinds. A plan falls due at the first occurrence after its last completion.
- Plans take `requiredQualifications` and calibrations take `qualifications` (qualification type keys). With `qualifications` installed, assigning a technician who lacks one to the plan's work order, or recording a calibration without them, fails with `MAINTENANCE_UNQUALIFIED`.
- Breaking for adopted tables: `maintenance_plans` gains `rrule`, `dtstart`, `tz` and `required_qualifications`, and `maintenance_calibrations` gains `qualifications`. Add them (the generated migration shows the definitions) before you upgrade.
