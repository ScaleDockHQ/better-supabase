---
"better-supabase": minor
---

pgTAP helpers `tests.import_run_fixture`, `tests.age_import_run`, `tests.bulk_touch_subjects` and `tests.assert_override_dispatches_all` set up a run in a chosen state, move its lease into the past, age stored import stamps and check that an override still dispatches every import entity.
