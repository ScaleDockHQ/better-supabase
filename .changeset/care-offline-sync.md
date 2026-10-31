---
"better-supabase": minor
---

The care blocks work offline on PowerSync.

- `powersync streams` and `gen.powersync.instances` accept `activities`, `observations` and `medications`. They need `authorization: "roles"`: a user syncs the organizations where their role holds the block's `read` key.
- `better-supabase/powersync` adds `progressNoteRoute`, `activityLinksRoute`, `observationRoute`, `medicationAdministrationRoute` and `careUploadOutcome`. Clinical conflicts (a dose already recorded, a locked note) land in `connector.rejected`.

No migration is needed.
