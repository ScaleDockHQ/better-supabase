# Example performance

Numbers of the Next.js example, taken on the production build with the testing API (seed tier, after). Written by `pnpm example:perf-report --write`; do not edit by hand.

## Pages as admin

217 routes measured, 910 database calls in total for one warm render of each.

Most database calls:

| Route                 | Calls |
| --------------------- | ----- |
| /crm/deals            | 15    |
| /inbox/[conversation] | 15    |
| /customers/[id]       | 12    |
| /rfqs/[id]            | 11    |
| /people/leave         | 9     |
| /qualifications       | 9     |
| /shop/inventory       | 8     |
| /warehouse            | 8     |
| /compliance           | 7     |
| /finance              | 7     |

Slowest warm renders (ms, wall time):

| Route                    | Ms   |
| ------------------------ | ---- |
| /funding                 | 2829 |
| /work                    | 1353 |
| /crm/segments            | 1309 |
| /assistant/guardrails    | 1118 |
| /medications             | 1093 |
| /settings/security       | 958  |
| /assistant/agents/memory | 879  |
| /crm/pipelines           | 860  |
| /funding/[id]            | 826  |
| /assistant/prompts       | 812  |

Routes with more than one token verification: none.

Routes with service-role calls: none.

## Pages as member

208 routes measured, 997 database calls in total for one warm render of each.

Most database calls:

| Route                       | Calls |
| --------------------------- | ----- |
| /inbox/[conversation]       | 19    |
| /crm/deals                  | 16    |
| /customers/[id]             | 13    |
| /people/leave               | 10    |
| /shop/inventory             | 9     |
| /funding                    | 8     |
| /people                     | 8     |
| /people/onboarding          | 8     |
| /people/leave/[id]          | 8     |
| /shop/inventory/[variantId] | 8     |

Slowest warm renders (ms, wall time):

| Route                    | Ms   |
| ------------------------ | ---- |
| /funding                 | 2059 |
| /rules                   | 1164 |
| /legal-entities          | 948  |
| /funding/[id]            | 882  |
| /maintenance/meters/[id] | 857  |
| /banking/accounts/[id]   | 854  |
| /maintenance             | 851  |
| /people/time             | 841  |
| /metrics                 | 836  |
| /lims/[id]               | 798  |

Routes with more than one token verification: none.

Routes with service-role calls: none.

## Actions as admin

| Action              | Calls | Waves | Ms     | Tables |
| ------------------- | ----- | ----- | ------ | ------ |
| loadMyOrganizations | 5     | 3     | 104.44 | 4      |
| loadMembers         | 7     | 2     | 65.12  | 6      |
| loadPlanCatalog     | 7     | 3     | 116.88 | 5      |
| loadInboxes         | 4     | 2     | 137.81 | 4      |
| loadTeams           | 0     | 0     | 0      | 0      |
| loadMacros          | 0     | 0     | 0      | 0      |
| loadDrafts          | 0     | 0     | 0      | 0      |
| loadScheduled       | 0     | 0     | 0      | 0      |
| loadInboundEvents   | 3     | 1     | 119.93 | 3      |
| loadConversations   | 3     | 1     | 106.33 | 3      |
| searchKnowledge     | 4     | 2     | 139.97 | 4      |

## Actions as member

| Action              | Calls | Waves | Ms     | Tables |
| ------------------- | ----- | ----- | ------ | ------ |
| loadMyOrganizations | 6     | 3     | 74.85  | 5      |
| loadMembers         | 7     | 3     | 85.07  | 6      |
| loadPlanCatalog     | 9     | 4     | 142.25 | 6      |
| loadInboxes         | 6     | 4     | 165.58 | 5      |
| loadTeams           | 0     | 0     | 0      | 0      |
| loadMacros          | 0     | 0     | 0      | 0      |
| loadDrafts          | 0     | 0     | 0      | 0      |
| loadScheduled       | 0     | 0     | 0      | 0      |
| loadInboundEvents   | 5     | 3     | 151.03 | 4      |
| loadConversations   | 4     | 2     | 114.71 | 4      |
| searchKnowledge     | 6     | 3     | 120.32 | 5      |

## Cold, warm and client navigation (admin)

217 routes. Median first hit after a server start 324 ms, second hit 232 ms, client navigation after prefetch 58 ms. Slowest first hits:

| Route         | Cold ms |
| ------------- | ------- |
| /funding      | 2520    |
| /medications  | 1368    |
| /payroll/[id] | 698     |
| /funding/[id] | 600     |
| /inbox        | 588     |

## First-load JavaScript

268 routes, median 1426128 B uncompressed. Largest:

| Route                       | Bytes   |
| --------------------------- | ------- |
| /projects                   | 1946563 |
| /crm/deals                  | 1679341 |
| /banking/accounts           | 1644879 |
| /banking/accounts/[id]      | 1644879 |
| /banking/transactions       | 1644879 |
| /banking/transactions/[id]  | 1644879 |
| /finance/accounting         | 1644879 |
| /finance/accounting/[id]    | 1644879 |
| /finance/billable-time      | 1644879 |
| /finance/billable-time/[id] | 1644879 |

Actions in the build: 471; measured: 11; not measured: 460.

## Authentication and permissions

| Scenario                      | Wall ms | Calls | Verifications | Proxy ms | Auth ms |
| ----------------------------- | ------- | ----- | ------------- | -------- | ------- |
| sign-in admin                 | 408     | -     | -             | 0.3      | 0.2     |
| warm / admin                  | 948     | 4     | 0             | 0.7      | 0.6     |
| warm /customers admin         | 909     | 6     | 0             | 0.5      | 0.3     |
| warm /finance/invoices admin  | 1017    | 3     | 0             | 2.3      | 2.1     |
| refresh /customers admin      | 897     | 6     | 2             | 0.5      | 0.4     |
| sign-in member                | 437     | -     | -             | 0.4      | 0.3     |
| warm / member                 | 938     | 5     | 0             | 0.4      | 0.3     |
| warm /customers member        | 1130    | 7     | 0             | 3.3      | 3.1     |
| warm /finance/invoices member | 1058    | 4     | 0             | 0.4      | 0.3     |
| refresh /customers member     | 851     | 7     | 2             | 0.5      | 0.3     |
