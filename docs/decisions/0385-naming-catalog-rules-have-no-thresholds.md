# 0385: The naming catalog rules have no thresholds

- Status: accepted
- Date: 2026-11-08
- Amends: 0247, 0380

## Context

`supabase/tests/database/naming_catalog.test.sql` counted the objects that still
used an old shape and allowed the count to stay at a number ("lower it when you
rename"). A new violation under the number passed.

## Decision

Every rule lists the objects that break it with `string_agg` and expects the
empty string, so a failure names them. The exceptions sit in the rule and say
why: `dtstart` (RFC 5545), `scim_user_id` (it references `scim_users`) and the
three fixture app functions that are security definer in `public`. Two rules
join the set: no column and no table of `better_supabase` uses the `engagement`
noun (ADR 0380).

## Not done

The rules for block names (`bulk-actions`, `ratings`, `time-entries`), the
config keys and the generated file layout of the naming plan are not in the
catalog, because those renames have not landed.
