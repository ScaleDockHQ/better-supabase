---
"better-supabase": minor
---

Add the `qms`, `ehs` and `isms` presets. `qms` installs SaaS with the quality blocks (controlled documents in the drive, cases, inspections, risks, qualifications, acknowledgements, courses, assets and metrics) and releases drive documents through an approvals policy. `ehs` installs the same blocks without posts or document control, and `isms` installs SaaS with compliance, risks, inspections, cases, acknowledgements and the drive. Each preset has a docs page, and `init --preset` and `add --preset` accept the new names. `codemod 0.47` now names the policy acknowledgement and sequence run items in its description, and the 0.46 to 0.47 guide gains before and after code for AI document versions and postmortem action items, plus a list of what 0.48 removes.
