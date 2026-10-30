---
"better-supabase": minor
---

Add the `shifts` block (`better-supabase/blocks/shifts`). Shift templates generate draft shifts on weekdays, planners publish them per team and location, and every assignment is checked for overlapping shifts, approved leave (leave block), required qualifications (qualifications block) and the minimum rest between shifts. Members ask for open shifts, offer a shift to a colleague and set their availability. `roster`, `myShifts` and `hours` read the plan, and `toTimeEntries` turns worked shifts into time entries (time-tracking block). The example app adds a `roster-board` recipe.
