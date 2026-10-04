---
"better-supabase": patch
---

The `permdock` access model reads PermDock's manifest itself. `better-supabase sql add` takes the helpers' schema from `rls.schema`, the scope from the root `rls.scopes` entry (the one without `within`) and the id type from that scope's `type`, whatever `entitlements.permdock` says, so a manifest with `rls.schema: "authz"` and a root scope `tenant` gets `authz.permitted_tenant_ids`. It stops instead of guessing when the manifest is missing, has no single root scope, or disagrees with `kits.access.permdock.scope`, `kits.access.permdock.schema` or `kits.access.idType`; 0.5.0 fell back to `permdock.permitted_organization_ids` and `uuid`. Code that renders the kit without the CLI (`renderKit`, `moduleBody`) now sets both `kits.access.permdock.schema` and `kits.access.permdock.scope`. Doctor reports the same problems, and helpers the manifest or the database lacks, as the new BS411 error.
