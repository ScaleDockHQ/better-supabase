# Example performance

Numbers of the Next.js example, taken on the production build with the testing API (seed tier). Written by `pnpm example:perf-report --write`; do not edit by hand.

## Pages as admin

252 routes measured, 703 database calls in total for one warm render of each.

Most database calls:

| Route                  | Calls |
| ---------------------- | ----- |
| /care/[clientId]       | 18    |
| /customers/[id]        | 14    |
| /crm/deals             | 13    |
| /inbox/[conversation]  | 13    |
| /crm/deals/[id]        | 13    |
| /field/dispatch/[id]   | 12    |
| /finance/invoices/[id] | 11    |
| /finance/payables/[id] | 11    |
| /people/leave          | 10    |
| /people/hiring/[id]    | 9     |

Slowest warm renders (ms, wall time):

| Route                       | Ms   |
| --------------------------- | ---- |
| /settings/marketplace       | 1205 |
| /content/[id]               | 1049 |
| /compliance/[framework]     | 996  |
| /banking/accounts/[id]      | 984  |
| /banking/transactions/[id]  | 942  |
| /documents/register         | 942  |
| /compliance/controls/[id]   | 922  |
| /banking/accounts           | 771  |
| /advisories/vulnerabilities | 730  |
| /people/encryption          | 728  |

Routes with more than one token verification: none.

Routes with service-role calls: none.

## Actions as admin

| Action                                                                        | Calls | Waves | Ms     | Tables |
| ----------------------------------------------------------------------------- | ----- | ----- | ------ | ------ |
| loadMyOrganizations                                                           | 3     | 3     | 41.39  | 3      |
| loadMembers                                                                   | 6     | 3     | 72.08  | 5      |
| loadPlanCatalog                                                               | 5     | 3     | 63.11  | 3      |
| loadInboxes                                                                   | 2     | 2     | 58.83  | 2      |
| loadTeams                                                                     | 13    | 4     | 137.59 | 10     |
| loadMacros                                                                    | 14    | 5     | 134.72 | 11     |
| loadDrafts                                                                    | 13    | 4     | 129.92 | 10     |
| loadScheduled                                                                 | 13    | 4     | 158.73 | 10     |
| loadInboundEvents                                                             | 1     | 1     | 25.35  | 1      |
| loadConversations                                                             | 1     | 1     | 41.99  | 1      |
| searchKnowledge                                                               | 2     | 2     | 37.11  | 2      |
| addObligation                                                                 | 4     | 2     | 124.26 | 2      |
| refreshSegment                                                                | 3     | 2     | 77.7   | 2      |
| closeDealLost                                                                 | 6     | 3     | 83.98  | 6      |
| acceptQuote                                                                   | 5     | 2     | 125.16 | 5      |
| payAndFulfilOrder                                                             | 5     | 2     | 55.44  | 5      |
| prescribeMedicationWithConsent                                                | 5     | 2     | 45.87  | 5      |
| publishCarePlan                                                               | 7     | 4     | 79.32  | 7      |
| archiveCarePlan                                                               | 7     | 4     | 214.6  | 7      |
| signPrescription                                                              | 3     | 3     | 59.46  | 3      |
| cancelPrescription                                                            | 4     | 4     | 115.76 | 3      |
| exportRecordSubject                                                           | 7     | 4     | 269.12 | 7      |
| approveAndInvoiceTimesheet                                                    | 6     | 3     | 68.74  | 4      |
| shareDriveWithRoles                                                           | 3     | 2     | 43.5   | 3      |
| createPublicLink                                                              | 3     | 2     | 68.29  | 3      |
| reconcileAccount                                                              | 2     | 2     | 58.96  | 2      |
| rotateKey                                                                     | 6     | 3     | 81.27  | 6      |
| inviteWithinSeats                                                             | 6     | 3     | 380.26 | 6      |
| decideApprovals                                                               | 5     | 4     | 87.83  | 4      |
| decideApproval                                                                | 0     | 0     | 0      | 0      |
| redeliverWebhook                                                              | 0     | 0     | 0      | 0      |
| completeVisit                                                                 | 6     | 3     | 86.98  | 6      |
| openTicket                                                                    | 4     | 2     | 101.25 | 4      |
| discussCase                                                                   | 4     | 2     | 110    | 4      |
| hireApplication                                                               | 7     | 4     | 208.5  | 7      |
| onboardEmployee                                                               | 8     | 2     | 98.47  | 4      |
| offboardEmployee                                                              | 8     | 2     | 86.58  | 4      |
| assignCourse                                                                  | 6     | 3     | 169.39 | 6      |
| bookWithReminder                                                              | 8     | 2     | 55.37  | 4      |
| completeOnboardingStep                                                        | 0     | 0     | 0      | 0      |
| closeAccountingPeriod                                                         | 2     | 2     | 37.53  | 2      |
| addControlEvidence                                                            | 2     | 2     | 34.9   | 2      |
| submitAppraisalReview                                                         | 4     | 3     | 64     | 4      |
| calibrateAppraisal                                                            | 4     | 3     | 85.92  | 4      |
| applyStandardDunningLevels                                                    | 4     | 2     | 66.71  | 4      |
| payDueBills                                                                   | 6     | 4     | 115.6  | 5      |
| requestOrderReturn                                                            | 5     | 2     | 43.82  | 5      |
| settleReturn                                                                  | 5     | 2     | 76.55  | 5      |
| releaseProductionOrder                                                        | 7     | 3     | 133.24 | 7      |
| completeProductionOrder                                                       | 7     | 3     | 90.41  | 7      |
| raiseFindingCase                                                              | 3     | 2     | 68.24  | 3      |
| closeInspection                                                               | 3     | 2     | 41.13  | 3      |
| features/assistant/assistant-slot/assistant-slot-actions.ts#loadAssistantSlot | 4     | 1     | 15.44  | 3      |
| features/inbox/inbox-actions.ts#loadMessage                                   | 4     | 1     | 12.71  | 3      |
| features/inbox/inbox-actions.ts#loadThread                                    | 4     | 1     | 35.69  | 3      |
| features/drive/drive-actions.ts#loadDriveSharing                              | 2     | 1     | 14.33  | 2      |
| features/people/people-actions.ts#getPrivateDetails                           | 0     | 0     | 0      | 0      |
| features/workflows/builder/builder-actions.ts#loadVersionGraph                | 1     | 1     | 34.06  | 1      |
| setProductStatus                                                              | 6     | 3     | 159.86 | 6      |
| setUpChangeWorkflow                                                           | 8     | 7     | 264.04 | 7      |
| createChangeRequest                                                           | 4     | 3     | 115.99 | 3      |
| moveChangeRequest                                                             | 4     | 3     | 109.75 | 4      |

## Cold, warm and client navigation (admin)

252 routes. Median first hit after a server start 201 ms, second hit 139 ms, client navigation after prefetch 28 ms. Slowest first hits:

| Route                            | Cold ms |
| -------------------------------- | ------- |
| /advisories/vulnerabilities/[id] | 1055    |
| /settings/support                | 1054    |
| /finance/ledger/[id]             | 1054    |
| /compliance/[framework]          | 1023    |
| /workflows/builder/[definition]  | 930     |

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

Actions in the build: 552; measured: 62; not measured: undefined.

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

Actions that expire the most tags:

| Action              | Tags |
| ------------------- | ---- |
| createChangeRequest | 15   |

## Authentication and permissions

| Scenario                      | Wall ms | Calls | Verifications | Proxy ms | Auth ms |
| ----------------------------- | ------- | ----- | ------------- | -------- | ------- |
| sign-in admin                 | 401     | -     | -             | 0.6      | 0.5     |
| size admin                    | -       | -     | -             | -        | -       |
| warm / admin                  | 674     | 2     | 0             | 0.4      | 0.3     |
| warm /customers admin         | 744     | 4     | 0             | 0.4      | 0.3     |
| warm /finance/invoices admin  | 706     | 3     | 0             | 0.3      | 0.2     |
| refresh /customers admin      | 640     | 0     | 1             | 24.6     | 23.5    |
| sign-in member                | 288     | -     | -             | 0.4      | 0.3     |
| size member                   | -       | -     | -             | -        | -       |
| warm / member                 | 611     | 2     | 0             | 0.2      | 0.1     |
| warm /customers member        | 684     | 4     | 0             | 0.3      | 0.2     |
| warm /finance/invoices member | 662     | 3     | 0             | 0.3      | 0.2     |
| refresh /customers member     | 684     | 0     | 0             | 33.8     | 33.2    |
