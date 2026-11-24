# Example performance

Numbers of the Next.js example, taken on the production build with the testing API (seed tier, before). Written by `pnpm example:perf-report --write`; do not edit by hand.

## Pages as admin

216 routes measured, 907 database calls in total for one warm render of each.

Most database calls:

| Route | Calls |
| --- | --- |
| /crm/deals | 15 |
| /inbox/[conversation] | 15 |
| /customers/[id] | 12 |
| /rfqs/[id] | 11 |
| /people/leave | 9 |
| /qualifications | 9 |
| /shop/inventory | 8 |
| /warehouse | 8 |
| /compliance | 7 |
| /finance | 7 |

Slowest warm renders (ms, wall time):

| Route | Ms |
| --- | --- |
| /funding | 2313 |
| /approvals | 1128 |
| /medications | 782 |
| /settings/roles | 782 |
| /crm/segments/[id] | 613 |
| /finance/payables | 509 |
| /crm/contracts/[id] | 491 |
| /finance/accounting | 488 |
| /settings/roles/[roleId] | 480 |
| /crm | 466 |

Routes with more than one token verification: none.

Routes with service-role calls: none.

## Pages as member

209 routes measured, 1002 database calls in total for one warm render of each.

Most database calls:

| Route | Calls |
| --- | --- |
| /inbox/[conversation] | 19 |
| /crm/deals | 16 |
| /customers/[id] | 13 |
| /people/leave | 10 |
| /shop/inventory | 9 |
| /funding | 8 |
| /people | 8 |
| /people/onboarding | 8 |
| /people/leave/[id] | 8 |
| /shop/inventory/[variantId] | 8 |

Slowest warm renders (ms, wall time):

| Route | Ms |
| --- | --- |
| /funding | 2246 |
| /medications | 1158 |
| /funding/[id] | 795 |
| /settings/billing/account | 461 |
| /announcements | 422 |
| /settings/roles/[roleId] | 383 |
| /deadlines | 377 |
| /people/encryption | 337 |
| /announcements/[id] | 334 |
| /banking/accounts | 325 |

Routes with more than one token verification: none.

Routes with service-role calls: none.

## Actions as admin

| Action | Calls | Waves | Ms | Tables |
| --- | --- | --- | --- | --- |
| loadMyOrganizations | 5 | 3 | 51.01 | 4 |
| loadMembers | 7 | 2 | 73.04 | 6 |
| loadPlanCatalog | 7 | 3 | 156.27 | 5 |
| loadInboxes | 4 | 2 | 109.71 | 4 |
| loadTeams | 0 | 0 | 0 | 0 |
| loadMacros | 0 | 0 | 0 | 0 |
| loadDrafts | 0 | 0 | 0 | 0 |
| loadScheduled | 0 | 0 | 0 | 0 |
| loadInboundEvents | 3 | 1 | 112.48 | 3 |
| loadConversations | 3 | 1 | 75.29 | 3 |
| searchKnowledge | 4 | 2 | 162.42 | 4 |

## Actions as member

| Action | Calls | Waves | Ms | Tables |
| --- | --- | --- | --- | --- |
| loadMyOrganizations | 6 | 3 | 149.92 | 5 |
| loadMembers | 7 | 3 | 105.07 | 6 |
| loadPlanCatalog | 9 | 4 | 204.19 | 6 |
| loadInboxes | 6 | 4 | 239.75 | 5 |
| loadTeams | 0 | 0 | 0 | 0 |
| loadMacros | 0 | 0 | 0 | 0 |
| loadDrafts | 0 | 0 | 0 | 0 |
| loadScheduled | 0 | 0 | 0 | 0 |
| loadInboundEvents | 5 | 3 | 266.86 | 4 |
| loadConversations | 4 | 2 | 87.15 | 4 |
| searchKnowledge | 6 | 3 | 119.08 | 5 |

## Cold, warm and client navigation (admin)

217 routes. Median first hit after a server start 320 ms, second hit 234 ms, client navigation after prefetch 58 ms. Slowest first hits:

| Route | Cold ms |
| --- | --- |
| /funding | 3039 |
| /medications | 972 |
| /funding/[id] | 895 |
| /imports | 699 |
| /payroll/[id] | 692 |

## First-load JavaScript

268 routes, median 1426128 B uncompressed. Largest:

| Route | Bytes |
| --- | --- |
| /projects | 1946563 |
| /crm/deals | 1679341 |
| /banking/accounts | 1644879 |
| /banking/accounts/[id] | 1644879 |
| /banking/transactions | 1644879 |
| /banking/transactions/[id] | 1644879 |
| /finance/accounting | 1644879 |
| /finance/accounting/[id] | 1644879 |
| /finance/billable-time | 1644879 |
| /finance/billable-time/[id] | 1644879 |

Actions in the build: 471; measured: 11; not measured: 460.

## Authentication and permissions

| Scenario | Wall ms | Calls | Verifications | Proxy ms | Auth ms |
| --- | --- | --- | --- | --- | --- |
| sign-in admin | 547 | - | - | 3 | 2.9 |
| warm / admin | 1327 | 4 | 0 | 0.4 | 0.3 |
| warm /customers admin | 1526 | 6 | 0 | 0.4 | 0.3 |
| warm /finance/invoices admin | 946 | 3 | 0 | 0.4 | 0.3 |
| refresh /customers admin | 1043 | 6 | 2 | 0.6 | 0.5 |
| sign-in member | 552 | - | - | 0.3 | 0.2 |
| warm / member | 803 | 5 | 0 | 0.4 | 0.3 |
| warm /customers member | 1118 | 7 | 0 | 0.6 | 0.5 |
| warm /finance/invoices member | 962 | 4 | 0 | 0.6 | 0.4 |
| refresh /customers member | 986 | 7 | 2 | 0.4 | 0.3 |

