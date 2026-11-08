---
"better-supabase": minor
---

The 0.46 and 0.47 rename shims are gone. Permission keys, event types, hint codes, subject types and entity keys from before those releases no longer resolve, and `upgrade` no longer rewrites the stored permission keys, event types and subject types. This removes `currentPermissionKeys`, `isOldPermissionKey`, `PERMISSION_KEY_RENAMES`, `PERMISSION_KEY_SPLITS`, `RENAMES_CODEMOD`, `currentEventTypes`, `isOldEventType`, `legacyEventType`, `legacyHintOf`, `HINT_RENAMES`, `ENTITY_KEY_RENAMES`, `EVENT_TYPE_RENAMES`, `EVENT_TYPE_SPLITS`, `SUBJECT_TYPE_RENAMES` and `PROGRAM_EVENT_MOVES`, the `formerKeys` config types, the audit and support action names `view` and `viewAll` (use `read` and `readAll`), the `automationSink` relay of old trigger names, and doctor BS422 to BS425.
