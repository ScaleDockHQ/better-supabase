# Example performance

Numbers of the Next.js example, taken on the production build with the testing API (seed tier). Written by `pnpm example:perf-report --write`; do not edit by hand.

## Pages as admin

239 routes measured, 656 database calls in total for one warm render of each.

Most database calls:

| Route                  | Calls |
| ---------------------- | ----- |
| /care/[clientId]       | 18    |
| /customers/[id]        | 14    |
| /crm/deals             | 13    |
| /inbox/[conversation]  | 13    |
| /field/dispatch/[id]   | 13    |
| /crm/deals/[id]        | 13    |
| /finance/invoices/[id] | 11    |
| /finance/payables/[id] | 11    |
| /people/leave          | 10    |
| /people/hiring/[id]    | 9     |

Slowest warm renders (ms, wall time):

| Route                     | Ms   |
| ------------------------- | ---- |
| /crm/deals                | 1260 |
| /crm/sequences            | 972  |
| /people/encryption        | 941  |
| /crm/companies            | 841  |
| /announcements            | 838  |
| /crm/quotes               | 812  |
| /settings/billing/account | 690  |
| /care-plans/[id]          | 620  |
| /crm/pipelines/[id]       | 605  |
| /crm/segments/[id]        | 543  |

Routes with more than one token verification: none.

Routes with service-role calls: none.

## Actions as admin

| Action                                                                        | Calls | Waves | Ms     | Tables |
| ----------------------------------------------------------------------------- | ----- | ----- | ------ | ------ |
| loadMyOrganizations                                                           | 3     | 3     | 63.63  | 3      |
| loadMembers                                                                   | 6     | 3     | 106.58 | 5      |
| loadPlanCatalog                                                               | 5     | 3     | 61.93  | 3      |
| loadInboxes                                                                   | 2     | 2     | 44.94  | 2      |
| loadTeams                                                                     | 13    | 4     | 139.35 | 10     |
| loadMacros                                                                    | 14    | 5     | 71.27  | 11     |
| loadDrafts                                                                    | 13    | 4     | 95.02  | 10     |
| loadScheduled                                                                 | 13    | 4     | 114.51 | 10     |
| loadInboundEvents                                                             | 1     | 1     | 28.1   | 1      |
| loadConversations                                                             | 1     | 1     | 28.03  | 1      |
| searchKnowledge                                                               | 2     | 2     | 39.66  | 2      |
| addObligation                                                                 | 4     | 2     | 80.63  | 2      |
| refreshSegment                                                                | 3     | 2     | 77.37  | 2      |
| closeDealLost                                                                 | 6     | 3     | 164.49 | 6      |
| acceptQuote                                                                   | 5     | 2     | 72.4   | 5      |
| payAndFulfilOrder                                                             | 5     | 2     | 40.3   | 5      |
| prescribeMedicationWithConsent                                                | 5     | 2     | 48.86  | 5      |
| publishCarePlan                                                               | 7     | 4     | 43.09  | 7      |
| archiveCarePlan                                                               | 7     | 4     | 118.67 | 7      |
| signPrescription                                                              | 3     | 3     | 71.43  | 3      |
| cancelPrescription                                                            | 4     | 4     | 40.23  | 3      |
| exportRecordSubject                                                           | 7     | 4     | 110.39 | 7      |
| approveAndInvoiceTimesheet                                                    | 6     | 3     | 62.43  | 4      |
| shareDriveWithRoles                                                           | 3     | 2     | 46.76  | 3      |
| createPublicLink                                                              | 3     | 2     | 30.46  | 3      |
| reconcileAccount                                                              | 2     | 2     | 101.23 | 2      |
| rotateKey                                                                     | 6     | 3     | 109.65 | 6      |
| inviteWithinSeats                                                             | 6     | 3     | 230.73 | 6      |
| decideApprovals                                                               | 5     | 4     | 51.23  | 4      |
| decideApproval                                                                | 0     | 0     | 0      | 0      |
| redeliverWebhook                                                              | 0     | 0     | 0      | 0      |
| completeVisit                                                                 | 6     | 3     | 65.14  | 6      |
| openTicket                                                                    | 4     | 2     | 128.8  | 4      |
| discussCase                                                                   | 4     | 2     | 114.2  | 4      |
| hireApplication                                                               | 7     | 4     | 174.46 | 7      |
| onboardEmployee                                                               | 8     | 2     | 69.43  | 4      |
| offboardEmployee                                                              | 8     | 2     | 64.38  | 4      |
| assignCourse                                                                  | 6     | 3     | 150.28 | 6      |
| bookWithReminder                                                              | 8     | 2     | 61.19  | 4      |
| completeOnboardingStep                                                        | 0     | 0     | 0      | 0      |
| closeAccountingPeriod                                                         | 2     | 2     | 36.65  | 2      |
| addControlEvidence                                                            | 2     | 2     | 27.37  | 2      |
| submitAppraisalReview                                                         | 4     | 3     | 51.3   | 4      |
| calibrateAppraisal                                                            | 4     | 3     | 35.28  | 4      |
| applyStandardDunningLevels                                                    | 4     | 2     | 84.31  | 4      |
| payDueBills                                                                   | 6     | 4     | 101.84 | 5      |
| requestOrderReturn                                                            | 5     | 2     | 50.6   | 5      |
| settleReturn                                                                  | 5     | 2     | 47.55  | 5      |
| releaseProductionOrder                                                        | 7     | 3     | 52.8   | 7      |
| completeProductionOrder                                                       | 7     | 3     | 95.58  | 7      |
| raiseFindingCase                                                              | 3     | 2     | 41.92  | 3      |
| closeInspection                                                               | 3     | 2     | 42.38  | 3      |
| features/assistant/assistant-slot/assistant-slot-actions.ts#loadAssistantSlot | 4     | 1     | 18.94  | 3      |
| features/inbox/inbox-actions.ts#loadMessage                                   | 4     | 1     | 19.98  | 3      |
| features/inbox/inbox-actions.ts#loadThread                                    | 4     | 1     | 8.22   | 3      |
| features/drive/drive-actions.ts#loadDriveSharing                              | 2     | 1     | 4.31   | 2      |
| features/people/people-actions.ts#getPrivateDetails                           | 0     | 0     | 0      | 0      |
| features/workflows/builder/builder-actions.ts#loadVersionGraph                | 1     | 1     | 9.1    | 1      |

## Cold, warm and client navigation (admin)

239 routes. Median first hit after a server start 198 ms, second hit 136 ms, client navigation after prefetch 29 ms. Slowest first hits:

| Route                            | Cold ms |
| -------------------------------- | ------- |
| /maintenance/meters/[id]         | 1070    |
| /advisories/vulnerabilities/[id] | 963     |
| /advisories/vulnerabilities      | 854     |
| /manufacturing                   | 830     |
| /people/leave/[id]               | 795     |

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

Actions in the build: 549; measured: 59; not measured: undefined.

## Caching

7 routes, each loaded as a hard load, a second hard load, a second user of the organization and on a restarted server (tests/cache.spec.ts). Calls are database calls summed over the routes; a ratio is the share of lookups a tier served.

| Scenario | Calls | Remote | Kept | Private | Public | Remote bytes read |
| -------- | ----- | ------ | ---- | ------- | ------ | ----------------- |
| hard1    | 25    | 0%     | 100% | 0%      | -      | 0                 |
| hard2    | 24    | 100%   | 100% | 0%      | -      | 325               |
| user2    | 25    | 0%     | 100% | 0%      | -      | 0                 |
| restart  | 25    | 0%     | 100% | 0%      | -      | 0                 |

Calls saved by the second hard load, by route:

| Route                 | Hard 1 | Hard 2 | User 2 | Restart | Kept bytes |
| --------------------- | ------ | ------ | ------ | ------- | ---------- |
| /                     | 2      | 2      | 2      | 2       | 8294       |
| /customers            | 4      | 4      | 4      | 4       | 8250       |
| /crm/deals            | 13     | 13     | 13     | 13      | 8250       |
| /finance/invoices     | 3      | 3      | 3      | 3       | 8250       |
| /settings/roles       | 1      | 1      | 1      | 1       | 8250       |
| /announcements        | 1      | 1      | 1      | 1       | 8250       |
| /islands?scope=remote | 1      | 0      | 1      | 1       | 0          |

No measured action expired a tag.

## Authentication and permissions

| Scenario | Wall ms | Calls | Verifications | Proxy ms | Auth ms |
| -------- | ------- | ----- | ------------- | -------- | ------- |
