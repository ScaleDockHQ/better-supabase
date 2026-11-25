# One round trip: before numbers

Measured on the production build with the testing API against the local stack, before the one-round-trip changes (branch `feat/examples-ports-area-gaps`, Track 0 harness). Warm render of each route; milliseconds are indicative, the counts are the budget. Routes with dynamic ids the seed has no row for are not in the page tables.

## Pages as admin

190 routes. Database calls 1016 (median 5), waves 216 (median 1), verifications 0, admin calls 0, cache hits 1, misses 0, first-render misses 0.

| Route            | Calls | Waves | Database ms |
| ---------------- | ----- | ----- | ----------- |
| /care/[clientId] | 21    | 2     | 544.76      |
| /customers/[id]  | 13    | 3     | 20          |
| /people/leave    | 13    | 1     | 17.97       |
| /content         | 10    | 1     | 13.23       |
| /people          | 10    | 1     | 15.57       |
| /qualifications  | 10    | 1     | 14.44       |
| /shop/inventory  | 9     | 1     | 17.98       |
| /warehouse       | 9     | 2     | 19.69       |
| /compliance      | 8     | 2     | 17.98       |
| /finance         | 8     | 1     | 18.76       |

Database time per warm render (pg_stat_statements, planning on): execution 5883 ms and planning 551 ms over 190 routes, 232506 buffers.

| Route                 | Exec ms | Plan ms | Statements | Buffers |
| --------------------- | ------- | ------- | ---------- | ------- |
| /funding              | 1790.73 | 1.97    | 14         | 52707   |
| /care/[clientId]      | 1203.12 | 3.93    | 25         | 30489   |
| /medications          | 480.32  | 2.05    | 12         | 10273   |
| /care                 | 359.92  | 6.58    | 20         | 16465   |
| /banking/transactions | 210.92  | 3.14    | 12         | 15041   |
| /settings/security    | 126.41  | 1.92    | 12         | 400     |
| /finance/ledger       | 87.66   | 3.18    | 12         | 2185    |
| /deadlines            | 81.16   | 2.61    | 11         | 3589    |
| /finance/invoices     | 70.99   | 2.54    | 12         | 1698    |
| /settings/audit       | 66.75   | 2.09    | 14         | 2582    |

## Actions as admin

54 actions. Calls 319, waves 101, verifications 0, cache hits 1, misses 0.

## Pages as member

197 routes. Database calls 1154 (median 5), waves 383 (median 2), verifications 0, admin calls 0, cache hits 1, misses 0, first-render misses 0.

| Route              | Calls | Waves | Database ms |
| ------------------ | ----- | ----- | ----------- |
| /customers/[id]    | 14    | 3     | 32.39       |
| /people/leave      | 14    | 1     | 25.2        |
| /care/[clientId]   | 12    | 3     | 131.65      |
| /content           | 11    | 2     | 25.21       |
| /people            | 10    | 2     | 24.3        |
| /shop/inventory    | 10    | 1     | 25.78       |
| /funding           | 9     | 1     | 876.8       |
| /people/onboarding | 9     | 1     | 22.62       |
| /people/leave/[id] | 9     | 1     | 24.49       |
| /projects/[id]     | 9     | 2     | 24.75       |

Database time per warm render (pg_stat_statements, planning on): execution 7633 ms and planning 553 ms over 197 routes, 471582 buffers.

| Route                     | Exec ms | Plan ms | Statements | Buffers |
| ------------------------- | ------- | ------- | ---------- | ------- |
| /funding                  | 1975.59 | 1.95    | 15         | 60301   |
| /settings/billing/credits | 402.82  | 11.46   | 16         | 25760   |
| /medications              | 408.35  | 2.2     | 13         | 11121   |
| /care                     | 380.03  | 3.79    | 17         | 19374   |
| /banking/transactions     | 323.57  | 2.66    | 13         | 26273   |
| /finance/invoices         | 214.32  | 2.86    | 13         | 16046   |
| /care/[clientId]          | 135.67  | 2.87    | 18         | 6140    |
| /deadlines                | 94.65   | 2.51    | 12         | 4551    |
| /documents                | 87.97   | 2.79    | 13         | 7819    |
| /settings/roles           | 88.18   | 2.19    | 12         | 24205   |

## Actions as member

54 actions. Calls 358, waves 153, verifications 0, cache hits 1, misses 0.

Action coverage: {"actions":545,"listed":49,"generatedReads":6,"covered":55,"skippedNeedArguments":490} (the rest need arguments the harness does not build).

## Auth and proxy cost

| Scenario                      | Doc ms | Calls | Waves | Verifications | Proxy ms | Auth ms |
| ----------------------------- | ------ | ----- | ----- | ------------- | -------- | ------- |
| warm / admin                  | 50     | 5     | 2     | 0             | 0.3      | 0.2     |
| warm /customers admin         | 51     | 7     | 1     | 0             | 0.4      | 0.3     |
| warm /finance/invoices admin  | 49     | 4     | 1     | 0             | 0.2      | 0.1     |
| refresh /customers admin      | 77     | 7     | 1     | 2             | 32.4     | 31.5    |
| warm / member                 | 40     | 6     | 2     | 0             | 0.2      | 0.1     |
| warm /customers member        | 47     | 8     | 2     | 0             | 0.3      | 0.2     |
| warm /finance/invoices member | 43     | 5     | 2     | 0             | 0.4      | 0.3     |
| refresh /customers member     | 86     | 8     | 2     | 3             | 33.8     | 33.4    |

| Role   | Token bytes | Cookie bytes | Chunks | Request header bytes |
| ------ | ----------- | ------------ | ------ | -------------------- |
| admin  | 4035        | 5567         | 2      | 5658                 |
| member | 1187        | 1770         | 1      | 1837                 |
