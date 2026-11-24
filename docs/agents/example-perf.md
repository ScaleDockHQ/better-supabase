# Example performance

Numbers of the Next.js example, taken on the production build with the testing API (seed tier). Written by `pnpm example:perf-report --write`; do not edit by hand.

## Pages as admin

237 routes measured, 1333 database calls in total for one warm render of each.

Most database calls:

| Route                  | Calls |
| ---------------------- | ----- |
| /care/[clientId]       | 21    |
| /crm/deals             | 16    |
| /inbox/[conversation]  | 16    |
| /people/leave          | 13    |
| /finance/invoices/[id] | 13    |
| /customers/[id]        | 13    |
| /people/hiring/[id]    | 12    |
| /rfqs/[id]             | 12    |
| /field/dispatch/[id]   | 11    |
| /content               | 10    |

Slowest warm renders (ms, wall time):

| Route                      | Ms   |
| -------------------------- | ---- |
| /care/[clientId]           | 1166 |
| /funding                   | 931  |
| /medications               | 517  |
| /funding/[id]              | 454  |
| /settings/security         | 453  |
| /settings/marketplace      | 272  |
| /care                      | 236  |
| /settings/roles/[roleId]   | 203  |
| /people/leave              | 164  |
| /settings/members/[userId] | 148  |

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
| loadMyOrganizations            | 6     | 2     | 30.67  | 5      |
| loadMembers                    | 9     | 3     | 28.64  | 8      |
| loadPlanCatalog                | 8     | 3     | 34.34  | 6      |
| loadInboxes                    | 5     | 2     | 31.72  | 5      |
| loadTeams                      | 0     | 0     | 0      | 0      |
| loadMacros                     | 0     | 0     | 0      | 0      |
| loadDrafts                     | 0     | 0     | 0      | 0      |
| loadScheduled                  | 0     | 0     | 0      | 0      |
| loadInboundEvents              | 4     | 1     | 19.85  | 4      |
| loadConversations              | 4     | 1     | 18.12  | 4      |
| searchKnowledge                | 5     | 2     | 28.28  | 5      |
| addObligation                  | 7     | 2     | 39.47  | 5      |
| refreshSegment                 | 6     | 2     | 34.6   | 5      |
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
| reconcileAccount               | 13    | 3     | 40.43  | 6      |
| rotateKey                      | 0     | 0     | 0      | 0      |
| inviteWithinSeats              | 11    | 5     | 142.23 | 10     |
| decideApprovals                | 0     | 0     | 0      | 0      |
| decideApproval                 | 0     | 0     | 0      | 0      |
| redeliverWebhook               | 3     | 1     | 11.32  | 3      |
| completeVisit                  | 0     | 0     | 0      | 0      |
| openTicket                     | 8     | 3     | 60.78  | 8      |
| discussCase                    | 7     | 2     | 59.34  | 7      |
| hireApplication                | 0     | 0     | 0      | 0      |
| onboardEmployee                | 12    | 3     | 48.65  | 8      |
| offboardEmployee               | 14    | 4     | 43.86  | 10     |
| assignCourse                   | 0     | 0     | 0      | 0      |
| bookWithReminder               | 11    | 2     | 34.37  | 7      |
| completeOnboardingStep         | 0     | 0     | 0      | 0      |
| closeAccountingPeriod          | 6     | 3     | 27.64  | 6      |
| payDueBills                    | 9     | 3     | 59.08  | 8      |
| requestOrderReturn             | 0     | 0     | 0      | 0      |
| settleReturn                   | 0     | 0     | 0      | 0      |
| releaseProductionOrder         | 0     | 0     | 0      | 0      |
| completeProductionOrder        | 0     | 0     | 0      | 0      |
| raiseFindingCase               | 0     | 0     | 0      | 0      |
| closeInspection                | 0     | 0     | 0      | 0      |
| setProductStatus               | 0     | 0     | 0      | 0      |

## Cold, warm and client navigation (admin)

237 routes. Median first hit after a server start 161 ms, second hit 113 ms, client navigation after prefetch 35 ms. Slowest first hits:

| Route            | Cold ms |
| ---------------- | ------- |
| /funding         | 990     |
| /care/[clientId] | 785     |
| /medications     | 594     |
| /funding/[id]    | 541     |
| /crm/contacts    | 493     |

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

Actions in the build: 544; measured: 46; not measured: 498.

## Authentication and permissions

| Scenario                      | Wall ms | Calls | Verifications | Proxy ms | Auth ms |
| ----------------------------- | ------- | ----- | ------------- | -------- | ------- |
| sign-in admin                 | 516     | -     | -             | 0.4      | 0.3     |
| warm / admin                  | 655     | 5     | 0             | 0.4      | 0.3     |
| warm /customers admin         | 764     | 7     | 0             | 0.4      | 0.3     |
| warm /finance/invoices admin  | 648     | 4     | 0             | 0.4      | 0.3     |
| refresh /customers admin      | 653     | 7     | 3             | 0.5      | 0.4     |
| sign-in member                | 208     | -     | -             | 0.2      | 0.1     |
| warm / member                 | 635     | 6     | 0             | 0.3      | 0.2     |
| warm /customers member        | 664     | 8     | 0             | 0.3      | 0.3     |
| warm /finance/invoices member | 682     | 5     | 0             | 0.3      | 0.2     |
| refresh /customers member     | 651     | 8     | 3             | 0.3      | 0.2     |
