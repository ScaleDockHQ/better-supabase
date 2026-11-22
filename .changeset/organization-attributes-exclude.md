---
"better-supabase": minor
---

`blocks.organizations.options.attributesExclude` keeps columns your schema files add to the organizations table out of `create_organization`, `update_organization` and `list_my_organizations`. Every other column you add stays an attribute without being listed in `attributes`. See ADR 1188.
