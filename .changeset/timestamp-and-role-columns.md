---
"better-supabase": minor
---

The last block columns that broke the naming rules are renamed: timestamp columns end in `_at`, and a user reference names the user's role. `better-supabase upgrade` writes a migration that renames them in place, so no row moves (vercel-marketplace 3, billing 5, impersonation 3); then run `db diff`. The SQL functions keep their parameter names (`period_start`, `period_end`), the support session rows keep their `target_user_id` key and TypeScript keeps `targetUserId`, `periodStart` and `periodEnd`. Code that selects the columns directly needs the new names.

| Table                                                                                                        | Old              | New                |
| ------------------------------------------------------------------------------------------------------------ | ---------------- | ------------------ |
| `marketplace_invoices`, `marketplace_meter_reports`, `billing_native_subscriptions`                          | `period_start`   | `period_starts_at` |
| `marketplace_invoices`, `marketplace_meter_reports`, `billing_native_subscriptions`, `billing_subscriptions` | `period_end`     | `period_ends_at`   |
| `support_sessions`, `support_requests`                                                                       | `target_user_id` | `target_id`        |

The `jsonb` that `create_native_subscription` returns names the period `period_starts_at` and `period_ends_at` too.
