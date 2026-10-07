---
"better-supabase": patch
---

The SQL modules' service-caller check reads `(select auth.jwt())`, so the read policies on `billing_customers` (the entitlements module's customer source), `usage_counters`, `usage_quotas` and `onboarding_progress` evaluate the token once per statement instead of once per row, and Supabase's performance advisor (doctor BS200, `auth_rls_initplan`) no longer flags them. Run `better-supabase sql sync` to rewrite the module files.
