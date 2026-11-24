# Example performance

Numbers of the Next.js example, taken on the production build with the testing API (seed tier, before). Written by `pnpm example:perf-report --write`; do not edit by hand.

## Pages as admin

207 routes measured, 856 database calls in total for one warm render of each.

Most database calls:

| Route                 | Calls |
| --------------------- | ----- |
| /inbox/[conversation] | 15    |
| /customers/[id]       | 12    |
| /rfqs/[id]            | 11    |
| /people/leave         | 9     |
| /qualifications       | 9     |
| /shop/inventory       | 8     |
| /warehouse            | 8     |
| /compliance           | 7     |
| /finance              | 7     |
| /funding              | 7     |

Slowest warm renders (ms, wall time):

| Route                    | Ms   |
| ------------------------ | ---- |
| /funding                 | 1886 |
| /medications             | 1215 |
| /compliance              | 837  |
| /funding/[id]            | 654  |
| /finance/ledger          | 525  |
| /crm/commissions         | 513  |
| /crm/scoring             | 494  |
| /calendar                | 482  |
| /settings/roles/[roleId] | 467  |
| /customers               | 466  |

Routes with more than one token verification: none.

Routes with service-role calls: none.

## Pages as member

198 routes measured, 930 database calls in total for one warm render of each.

Most database calls:

| Route                       | Calls |
| --------------------------- | ----- |
| /inbox/[conversation]       | 19    |
| /customers/[id]             | 13    |
| /people/leave               | 10    |
| /shop/inventory             | 9     |
| /people                     | 8     |
| /people/onboarding          | 8     |
| /people/leave/[id]          | 8     |
| /shop/inventory/[variantId] | 8     |
| /shop/inventory/lots        | 8     |
| /shop/inventory/movements   | 8     |

Slowest warm renders (ms, wall time):

| Route                    | Ms   |
| ------------------------ | ---- |
| /courses                 | 1540 |
| /medications             | 1335 |
| /settings/jobs/runs      | 1210 |
| /finance                 | 1086 |
| /settings/oauth-apps     | 973  |
| /crm/quotes              | 856  |
| /settings/preferences    | 846  |
| /funding/[id]            | 789  |
| /settings/roles/[roleId] | 439  |
| /announcements           | 384  |

Routes with more than one token verification: none.

Routes with service-role calls: none.

## Actions as admin

| Action              | Calls | Waves | Ms     | Tables |
| ------------------- | ----- | ----- | ------ | ------ |
| loadMyOrganizations | 5     | 3     | 71.59  | 4      |
| loadMembers         | 7     | 2     | 74.96  | 6      |
| loadPlanCatalog     | 7     | 3     | 95.47  | 5      |
| loadInboxes         | 4     | 2     | 195.92 | 4      |
| loadTeams           | 0     | 0     | 0      | 0      |
| loadMacros          | 0     | 0     | 0      | 0      |
| loadDrafts          | 0     | 0     | 0      | 0      |
| loadScheduled       | 0     | 0     | 0      | 0      |
| loadInboundEvents   | 3     | 1     | 50.16  | 3      |
| loadConversations   | 3     | 1     | 98.13  | 3      |
| searchKnowledge     | 4     | 2     | 136.06 | 4      |

## Actions as member

| Action              | Calls | Waves | Ms     | Tables |
| ------------------- | ----- | ----- | ------ | ------ |
| loadMyOrganizations | 6     | 3     | 88.48  | 5      |
| loadMembers         | 7     | 3     | 143.02 | 6      |
| loadPlanCatalog     | 9     | 4     | 110.69 | 6      |
| loadInboxes         | 6     | 4     | 310.82 | 5      |
| loadTeams           | 0     | 0     | 0      | 0      |
| loadMacros          | 0     | 0     | 0      | 0      |
| loadDrafts          | 0     | 0     | 0      | 0      |
| loadScheduled       | 0     | 0     | 0      | 0      |
| loadInboundEvents   | 5     | 3     | 113.19 | 4      |
| loadConversations   | 4     | 2     | 56.47  | 4      |
| searchKnowledge     | 6     | 3     | 151.73 | 5      |

## Cold, warm and client navigation (admin)

207 routes. Median first hit after a server start 319 ms, second hit 232 ms, client navigation after prefetch 59 ms. Slowest first hits:

| Route                    | Cold ms |
| ------------------------ | ------- |
| /funding                 | 2551    |
| /medications             | 1527    |
| /settings/security       | 601     |
| /settings/roles/[roleId] | 591     |
| /funding/[id]            | 589     |

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

Actions in the build: 458; measured: 11; not measured: 447.

## Authentication and permissions

| Scenario                      | Wall ms | Calls | Verifications | Proxy ms | Auth ms |
| ----------------------------- | ------- | ----- | ------------- | -------- | ------- |
| sign-in admin                 | 615     | -     | -             | 0.3      | 0.2     |
| warm / admin                  | 983     | 4     | 0             | 0.6      | 0.5     |
| warm /customers admin         | 1266    | 6     | 0             | 0.6      | 0.5     |
| warm /finance/invoices admin  | 1679    | 3     | 0             | 0.5      | 0.3     |
| sign-in member                | 450     | -     | -             | 0.4      | 0.3     |
| warm / member                 | 952     | 5     | 0             | 0.4      | 0.3     |
| warm /customers member        | 963     | 7     | 0             | 0.4      | 0.3     |
| warm /finance/invoices member | 984     | 4     | 0             | 0.4      | 0.3     |
| refresh /customers member     | 863     | 7     | 2             | 0.4      | 0.3     |
| refresh /customers admin      | 906     | 6     | 2             | 0.6      | 0.5     |
