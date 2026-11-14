---
"better-supabase": minor
---

Eleven list entities of the commerce blocks page, facet and count through the shared list function (ADR 0769): commission, commission statement and commission plan, donation gifts and pledges, leases, production orders, periods, referrals and referral codes, and shipments. Each client gets `<x>Page`, `<x>Facets` and `<x>Count` (`commissionPage`, `statementPage`, `planPage`, `giftPage`, `pledgePage`, `leasePage`, `orderPage`, `periodPage`, `referralPage`, `codePage` and `shipmentPage`), and each entity declares `sorts`, `facets` and `filters` in its manifest. The SQL functions `list_leases`, `list_shipments`, `list_gifts` and `list_pledges` now take `(tenant, filters jsonb)` instead of one argument per filter, and `list_production_orders` names its argument `filters`. The clients' `list`, `gifts`, `pledges` and `listOrders` methods are unchanged. Apply the generated migration, and change a direct SQL call to pass the filters as a jsonb object.

| Before                                                                        | After                                                                     |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `list_leases(tenant, 'active', unit, null, null, 50)`                         | `list_leases(tenant, '{"status":"active","unitId":"...","limit":50}')`    |
| `list_shipments(tenant, 'draft', null, null, 'dhl', null, 50)`                | `list_shipments(tenant, '{"status":"draft","carrier":"dhl","limit":50}')` |
| `list_gifts` and `list_pledges` with `donor_type`, `donor_id` and `page_size` | `filters` with `donorType`, `donorId` and `limit`                         |
| `list_production_orders(tenant, filter => '{"status":"done"}')`               | `list_production_orders(tenant, filters => '{"status":"done"}')`          |
| One status per list call                                                      | `<x>Page({ filters: { status: ["open", "done"] } })`, a list per filter   |
| No facet counts or exact counts for these lists                               | `<x>Facets()` and `<x>Count()` return `{ value, exact }`                  |
