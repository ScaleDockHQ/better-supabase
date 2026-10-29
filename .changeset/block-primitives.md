---
"better-supabase": minor
---

Small block additions for quality management:

- `settings`: `better_supabase.organization_setting(tenant, key)` returns one organization setting to other modules' security definer functions. Only `service_role` and the module schema's owner may execute it.
- `employees`: every employee event carries `userId` (null for an employee without an account), `employee.offboarded` included. `EmployeeEventData.userId` is now `string | null` instead of optional.
- `courses`: a course takes `validForMonths` (1 to 240), and its certificates get `expiresAt`. `verifyCertificate` returns `expired` and `expiresAt`, and an expired certificate is no longer `valid`. `course_certificate.issued` carries `expiresAt`.
- `signatures`: `request` takes a `meaning`, one of `blocks.signatures.options.meanings` (default `authored`, `reviewed`, `approved`, `released`, `acknowledged`). Requests return it and `signature.completed` carries it; another value fails with `SIGNATURE_REQUEST_MEANING_UNKNOWN`.
- `compliance`: a framework has a `kind` (`standard`, `legal`, `internal` or `contract`), and a control takes a `source` and a `jurisdiction`, for legal registers.

Run `better-supabase upgrade` and generate a migration to add the columns and the new function signatures.
