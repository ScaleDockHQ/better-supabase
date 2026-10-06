---
"better-supabase": minor
---

Usage quotas can follow the billing cycle: the `billing` period reads the current window from the app's `usage_billing_period(tenant)` function (falling back to the calendar month), and `usage_status` returns `starts_at` and `resets_at` for it. `sql.modules.usage.options.meters` is a meter catalog with a unit, category and label per meter: other meters are refused (`USAGE_METER_UNKNOWN`), `usage_status` returns the fields, and `usage.meters()` reads the catalog. The docs show weighted quantities for credits and a `customer` reader for `reportUsageToStripe`.
