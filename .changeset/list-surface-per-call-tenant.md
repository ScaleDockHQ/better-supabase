---
"better-supabase": minor
---

The shared list surface takes the organization per call (ADR 0939). `entityList` accepts `organizationId` in the options of `page`, `facets` and `count`, with `tenantOrOption` as the resolver and `RequiredTenantOption` for a block that has no `tenant` option. The `domains`, `forms`, `imports` and `access-requests` blocks use it: `hostname`, `form`, `import` (the runs) and `access_request` declare `sorts`, `facets` and `filters` in their manifests, and `domains.page`, `forms.page`, `imports.runs.page` and `accessRequests.page` come with `facets` and `count`, each taking `organizationId`. The SQL functions `list_hostnames`, `list_forms`, `list_import_runs` and `list_access_requests` now take `(tenant, filters jsonb)`. The capped `list` of each client sends the same filters as before; `domains.list` and `forms.list` now return at most 200 rows by default and 500 at most, where they were unbounded. Apply the generated migration before you upgrade the client, because the old client calls the old argument lists.

| Before                                                          | After                                                                          |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `list_hostnames(tenant)`                                        | `list_hostnames(tenant, filters)`                                              |
| `list_forms(tenant, status)`                                    | `list_forms(tenant, filters)` with `filters.status`                            |
| `list_import_runs(tenant, source, status, row_limit)`           | `list_import_runs(tenant, filters)` with `filters.source`, `.status`, `.limit` |
| `list_access_requests(tenant, status, mine, page_size, before)` | `list_access_requests(tenant, filters)` with the same names as filters         |
| `list_import_runs` returned `setof jsonb`                       | It returns one `jsonb` array, or a page object with `paged`                    |
| `domains.list` and `forms.list` were unbounded                  | Capped at 200 by default, 500 at most; use `page` past that                    |
| No sort, facets or count for these four lists                   | `page`, `facets()`, `count()` and `sort: { by }` from the declared `sorts`     |
| `entityList` read only the block's `tenant` option              | `organizationId` per call wins, then `tenant`, else `TENANT_REQUIRED`          |
