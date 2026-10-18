---
"better-supabase": patch
---

`doctor` reports fewer false warnings on block schemas. BS206 no longer counts a policy that already calls a security definer helper as `(select helper())` with no arguments, such as `session_active()`. BS213 counts a tenant column pinned by `better_supabase.can('tenant', column, ...)` or `column in (select better_supabase.tenant_ids_with(...))` like one pinned to `current_tenant_id()`, and leaves out a block's soft-delete column that a write can set but never clear, such as `comments.deleted_at`. Blocks declare those columns with the new `SqlModule.hidingColumns`, and `better-supabase/sql` exports `moduleHidingColumns`.

The generated app-tables pgTAP test now expects the `bs_session_active` policy on the tables that `blocks.sessions.options.policies` covers.
