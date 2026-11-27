---
"better-supabase": minor
---

Security fix: `sameTenant.auto` no longer drops a generated `bsb_same_tenant_<column>` check because an app trigger merely reads `new.<column>` or `old.<column>`. Such a trigger silently removed the cross-tenant check on that foreign key. A trigger now turns the check off only when its function declares `@bsb same-tenant-guard column=<column>`. Doctor BS398 warns when a marked trigger never mentions the tenant column, and the new info finding BS733 lists every column a marker turns the check off for. Run `better-supabase upgrade` and generate a migration: columns that lost their check get it back. Add the marker to an app trigger that really compares the tenant if you want only one check (ADR 1268).
