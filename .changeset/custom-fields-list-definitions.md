---
"better-supabase": minor
---

The custom-fields client gains `listDefinitions(organizationId, entity)`, which returns an entity's field definitions in rank order with their rank keys, so a settings page can show and reorder them. It calls the new SQL function `list_field_definitions(tenant, entity)`, which needs `custom_fields.read`. Run `better-supabase sql sync` to install it.
