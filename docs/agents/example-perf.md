# Example performance

Numbers of the Next.js example, taken on the production build with the testing API (seed tier). Written by `pnpm example:perf-report --write`; do not edit by hand.

## Pages as admin

238 routes measured, 1360 database calls in total for one warm render of each.

Most database calls:

| Route                  | Calls |
| ---------------------- | ----- |
| /care/[clientId]       | 21    |
| /crm/deals             | 16    |
| /crm/deals/[id]        | 16    |
| /inbox/[conversation]  | 16    |
| /field/dispatch/[id]   | 15    |
| /people/leave          | 13    |
| /finance/invoices/[id] | 13    |
| /customers/[id]        | 13    |
| /finance/payables/[id] | 13    |
| /people/hiring/[id]    | 12    |

Slowest warm renders (ms, wall time):

| Route                     | Ms  |
| ------------------------- | --- |
| /funding                  | 975 |
| /settings/billing/account | 792 |
| /finance/accounting       | 704 |
| /care-plans               | 697 |
| /announcements/[id]       | 689 |
| /care/[clientId]          | 671 |
| /customers                | 561 |
| /beta                     | 515 |
| /crm/deals/[id]           | 510 |
| /finance/expenses/[id]    | 478 |

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
| loadMyOrganizations            | 6     | 2     | 44.95  | 5      |
| loadMembers                    | 9     | 3     | 133.26 | 8      |
| loadPlanCatalog                | 8     | 3     | 75.42  | 6      |
| loadInboxes                    | 5     | 2     | 201.75 | 5      |
| loadTeams                      | 0     | 0     | 0      | 0      |
| loadMacros                     | 0     | 0     | 0      | 0      |
| loadDrafts                     | 0     | 0     | 0      | 0      |
| loadScheduled                  | 0     | 0     | 0      | 0      |
| loadInboundEvents              | 4     | 1     | 27.69  | 4      |
| loadConversations              | 4     | 1     | 49.63  | 4      |
| searchKnowledge                | 5     | 2     | 47.58  | 5      |
| addObligation                  | 7     | 2     | 96.56  | 5      |
| refreshSegment                 | 6     | 2     | 57.85  | 5      |
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
| reconcileAccount               | 13    | 3     | 95.06  | 6      |
| rotateKey                      | 0     | 0     | 0      | 0      |
| inviteWithinSeats              | 11    | 5     | 314.39 | 10     |
| decideApprovals                | 0     | 0     | 0      | 0      |
| decideApproval                 | 0     | 0     | 0      | 0      |
| redeliverWebhook               | 3     | 1     | 24.31  | 3      |
| completeVisit                  | 0     | 0     | 0      | 0      |
| openTicket                     | 8     | 3     | 108.93 | 8      |
| discussCase                    | 7     | 2     | 231.96 | 7      |
| hireApplication                | 0     | 0     | 0      | 0      |
| onboardEmployee                | 12    | 3     | 158.88 | 8      |
| offboardEmployee               | 14    | 4     | 88.64  | 10     |
| assignCourse                   | 0     | 0     | 0      | 0      |
| bookWithReminder               | 11    | 2     | 28.18  | 7      |
| completeOnboardingStep         | 0     | 0     | 0      | 0      |
| closeAccountingPeriod          | 6     | 3     | 63.77  | 6      |
| payDueBills                    | 9     | 4     | 165.36 | 8      |
| requestOrderReturn             | 0     | 0     | 0      | 0      |
| settleReturn                   | 0     | 0     | 0      | 0      |
| releaseProductionOrder         | 0     | 0     | 0      | 0      |
| completeProductionOrder        | 0     | 0     | 0      | 0      |
| raiseFindingCase               | 0     | 0     | 0      | 0      |
| closeInspection                | 0     | 0     | 0      | 0      |
| setProductStatus               | 0     | 0     | 0      | 0      |

## Cold, warm and client navigation (admin)

238 routes. Median first hit after a server start 162 ms, second hit 116 ms, client navigation after prefetch 25 ms. Slowest first hits:

| Route                     | Cold ms |
| ------------------------- | ------- |
| /funding                  | 1135    |
| /settings/billing/account | 929     |
| /assistant/activity       | 850     |
| /care/[clientId]          | 765     |
| /banking/accounts         | 764     |

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
| sign-in admin                 | 293     | -     | -             | 0.3      | 0.3     |
| warm / admin                  | 638     | 5     | 0             | 0.3      | 0.2     |
| warm /customers admin         | 680     | 7     | 0             | 0.2      | 0.2     |
| warm /finance/invoices admin  | 711     | 4     | 0             | 0.4      | 0.3     |
| refresh /customers admin      | 652     | 7     | 2             | 0.4      | 0.3     |
| sign-in member                | 161     | -     | -             | 0.2      | 0.2     |
| warm / member                 | 637     | 6     | 0             | 0.2      | 0.2     |
| warm /customers member        | 688     | 8     | 0             | 0.4      | 0.3     |
| warm /finance/invoices member | 631     | 5     | 0             | 0.3      | 0.2     |
| refresh /customers member     | 659     | 8     | 2             | 0.6      | 0.4     |
