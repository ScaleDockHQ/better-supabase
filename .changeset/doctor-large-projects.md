---
"better-supabase": minor
---

`doctor` checks `--out` before it reads the project, so a path outside the project or a directory fails at once instead of after the run. It logs the time of each phase, prints the times under the text report and lists them as `phases` in the JSON report (`doctor-report-v1.json`). A text report of 20 findings or more starts with one line per rule and its count. BS609 prints the read set that replaces the parallel reads it found, with `s` as the builder and one key per table.
