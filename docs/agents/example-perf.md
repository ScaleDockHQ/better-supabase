# Example performance

Numbers of the Next.js example, taken on the production build with the testing API (seed tier). Written by `pnpm example:perf-report --write`; do not edit by hand.

## Pages as admin

238 routes measured, 1345 database calls in total for one warm render of each.

Most database calls:

| Route                  | Calls |
| ---------------------- | ----- |
| /care/[clientId]       | 21    |
| /crm/deals             | 16    |
| /inbox/[conversation]  | 16    |
| /people/leave          | 13    |
| /finance/invoices/[id] | 13    |
| /customers/[id]        | 13    |
| /finance/payables/[id] | 13    |
| /people/hiring/[id]    | 12    |
| /rfqs/[id]             | 12    |
| /field/dispatch/[id]   | 11    |

Slowest warm renders (ms, wall time):

| Route                   | Ms   |
| ----------------------- | ---- |
| /finance/invoices/[id]  | 2967 |
| /finance/payables/[id]  | 2495 |
| /shop                   | 1499 |
| /finance/recurring/[id] | 1350 |
| /funding                | 1283 |
| /care/[clientId]        | 1259 |
| /finance/tax/[id]       | 1255 |
| /forms                  | 1236 |
| /banking/accounts       | 1068 |
| /assistant/usage        | 1059 |

Routes with more than one token verification: none.

Routes with service-role calls: none.

## Pages as member

226 routes measured, 1406 database calls in total for one warm render of each.

Most database calls:

| Route                  | Calls |
| ---------------------- | ----- |
| /inbox/[conversation]  | 20    |
| /crm/deals             | 17    |
| /finance/invoices/[id] | 14    |
| /finance/payables/[id] | 14    |
| /customers/[id]        | 14    |
| /people/leave          | 14    |
| /people/hiring/[id]    | 13    |
| /care/[clientId]       | 12    |
| /field/dispatch/[id]   | 12    |
| /content               | 11    |

Slowest warm renders (ms, wall time):

| Route                    | Ms  |
| ------------------------ | --- |
| /funding                 | 913 |
| /medications             | 457 |
| /funding/[id]            | 424 |
| /shop/kitchen/board      | 179 |
| /settings/roles/[roleId] | 174 |
| /care/[clientId]         | 155 |
| /documents               | 153 |
| /care-plans              | 150 |
| /work/grid               | 150 |
| /customers/[id]          | 149 |

Routes with more than one token verification: none.

Routes with service-role calls: none.

## Actions as admin

| Action                         | Calls | Waves | Ms     | Tables |
| ------------------------------ | ----- | ----- | ------ | ------ |
| loadMyOrganizations            | 6     | 2     | 52.01  | 5      |
| loadMembers                    | 9     | 3     | 117.32 | 8      |
| loadPlanCatalog                | 8     | 3     | 175.39 | 6      |
| loadInboxes                    | 5     | 2     | 82.93  | 5      |
| loadTeams                      | 0     | 0     | 0      | 0      |
| loadMacros                     | 0     | 0     | 0      | 0      |
| loadDrafts                     | 0     | 0     | 0      | 0      |
| loadScheduled                  | 0     | 0     | 0      | 0      |
| loadInboundEvents              | 4     | 1     | 38.72  | 4      |
| loadConversations              | 4     | 1     | 63.06  | 4      |
| searchKnowledge                | 5     | 2     | 52.84  | 5      |
| addObligation                  | 7     | 2     | 103.46 | 5      |
| refreshSegment                 | 6     | 2     | 109.25 | 5      |
| closeDealLost                  | 0     | 0     | 0      | 0      |
| acceptQuote                    | 0     | 0     | 0      | 0      |
| payAndFulfilOrder              | 0     | 0     | 0      | 0      |
| publishEntryWithVersion        | 0     | 0     | 0      | 0      |
| prescribeMedicationWithConsent | 0     | 0     | 0      | 0      |
| publishCarePlan                | 0     | 0     | 0      | 0      |
| archiveCarePlan                | 0     | 0     | 0      | 0      |
| signPrescription               | 0     | 0     | 0      | 0      |
| cancelPrescription             | 0     | 0     | 0      | 0      |
| exportRecordSubject            | 0     | 0     | 0      | 0      |
| reconcileAccount               | 13    | 3     | 222.16 | 6      |
| rotateKey                      | 0     | 0     | 0      | 0      |
| inviteWithinSeats              | 11    | 5     | 371.62 | 10     |
| decideApprovals                | 0     | 0     | 0      | 0      |
| decideApproval                 | 0     | 0     | 0      | 0      |
| redeliverWebhook               | 3     | 1     | 19.99  | 3      |
| completeVisit                  | 0     | 0     | 0      | 0      |
| openTicket                     | 8     | 3     | 166.17 | 8      |
| discussCase                    | 7     | 2     | 129.01 | 7      |
| hireApplication                | 0     | 0     | 0      | 0      |
| onboardEmployee                | 12    | 3     | 120.09 | 8      |
| offboardEmployee               | 14    | 4     | 135.15 | 10     |
| assignCourse                   | 0     | 0     | 0      | 0      |
| bookWithReminder               | 11    | 2     | 69.58  | 7      |
| completeOnboardingStep         | 0     | 0     | 0      | 0      |
| closeAccountingPeriod          | 6     | 3     | 56.69  | 6      |
| payDueBills                    | 9     | 4     | 155.14 | 8      |
| requestOrderReturn             | 0     | 0     | 0      | 0      |
| settleReturn                   | 0     | 0     | 0      | 0      |
| releaseProductionOrder         | 0     | 0     | 0      | 0      |
| completeProductionOrder        | 0     | 0     | 0      | 0      |
| raiseFindingCase               | 0     | 0     | 0      | 0      |
| closeInspection                | 0     | 0     | 0      | 0      |
| setProductStatus               | 0     | 0     | 0      | 0      |

## Cold, warm and client navigation (admin)

238 routes. Median first hit after a server start 202 ms, second hit 149 ms, client navigation after prefetch 28 ms. Slowest first hits:

| Route                            | Cold ms |
| -------------------------------- | ------- |
| /advisories/vulnerabilities/[id] | 4848    |
| /legal-entities/[id]             | 3064    |
| /payroll/[id]                    | 2441    |
| /finance/payables/[id]           | 2177    |
| /finance/accounting/[id]         | 2161    |

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

Actions in the build: 543; measured: 46; not measured: 497.

## Authentication and permissions

| Scenario                      | Wall ms | Calls | Verifications | Proxy ms | Auth ms |
| ----------------------------- | ------- | ----- | ------------- | -------- | ------- |
| sign-in admin                 | 302     | -     | -             | 0.3      | 0.2     |
| warm / admin                  | 654     | 5     | 0             | 0.6      | 0.5     |
| warm /customers admin         | 663     | 7     | 0             | 0.6      | 0.5     |
| warm /finance/invoices admin  | 700     | 4     | 0             | 0.4      | 0.3     |
| refresh /customers admin      | 635     | 7     | 2             | 0.3      | 0.2     |
| sign-in member                | 160     | -     | -             | 0.2      | 0.2     |
| warm / member                 | 632     | 6     | 0             | 0.3      | 0.2     |
| warm /customers member        | 653     | 8     | 0             | 0.4      | 0.3     |
| warm /finance/invoices member | 637     | 5     | 0             | 0.3      | 0.2     |
| refresh /customers member     | 675     | 8     | 2             | 0.6      | 0.4     |
