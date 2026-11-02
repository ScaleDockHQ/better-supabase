---
"better-supabase": minor
---

`notifications` gets digests: `notification_preferences` has a `cadence` (`immediate`, `daily`, `weekly` or `off`), a daily or weekly delivery is held, the `digest_run` housekeeping job folds held deliveries into `notification_digests`, and `createNotificationDigests` sends each as one email through the `mail-sync` mailer. `set_notification_cadence` sets the choice. The `consents` block adds `requires_consent(subject_type, subject_id, purpose_key)` and a `consents` contribution key for system purposes. `sequences` email steps take `consentPurpose` and `send` in `notifications` takes `consentPurpose`; both skip a send while the subject has no consent. Existing apps run `better-supabase db diff` to pick up the new column, table and functions.
