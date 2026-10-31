---
"better-supabase": minor
---

New `dam` block (`better-supabase/blocks/dam`): renditions of drive files and usage rights with a territory, a channel and an expiry date.

- `renderRenditions` makes the kinds you configure through the drive's `PreviewRenderer` port, stores the page and records the rendition. A renderer that throws leaves a `failed` rendition and the other kinds go on. `recordRendition` and `listRenditions` work with renditions your own job makes.
- `grantRight`, `revokeRight` and `listRights` keep usage rights. A right without a territory or channel covers all of them, and a revoked right stays in the history.
- `checkUsage` answers whether a file may be used on a day in a territory and channel.
- `notifyExpiring` notifies the member who granted each right that ends soon, once per expiry date.
- The permission keys are `dam.read` and `dam.write`.

Run `better-supabase add dam` and generate a migration. Call `notifyExpiring` on a schedule.
