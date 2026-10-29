---
"better-supabase": minor
---

Add the `qualifications` block (`better-supabase/blocks/qualifications`) for certifications, licences and skills that members, companies and assets hold:

- Qualification types with a validity in months and optional evidence, and requirements that name who must hold them: a role, a team, a job title, an asset kind, a segment or one holder.
- Holdings that expire, granted by hand or from a course certificate when the type names the course. Revoking keeps the holding with its reason.
- `gaps(organizationId, { holderType, holderId, teamId, typeKey, status })` lists the required qualifications holders lack, have let lapse or are about to lose (`better_supabase.qualification_gaps`). A member may read their own gaps without `qualifications.read`.
- `qualifiedHolders(organizationId, typeKey, { holderType, on })` returns the holders with a valid holding on a day (`better_supabase.qualified_holders`).
- `notifyExpiring()` reports each holding once when it enters the renewal window (`qualification.expiry_warned`) and once when it expires (`qualification.expired`).
- The `qualification-matrix` and `my-qualifications` UI recipes.

Admins get `qualifications.read`, `qualifications.grant` and `qualifications.manage`. Add `qualifications: {}` to `blocks`, run `better-supabase upgrade` and generate a migration. A permission catalog lists each key per role, so add the three keys to the roles that should hold them.
