# Block consistency audit

This audit reads the block catalog (`packages/better-supabase/src/blocks`), its manifests, clients, hooks, generators, docs and skills against what the example app (`apps/examples/nextjs`) had to build by hand. The goal is one predictable developer experience, and breaking changes are acceptable. Each gap has a finding row in [`example-findings.md`](example-findings.md) (EX-1200 to EX-1354). This is a report; no library code changed.

## Method and limits

- 195 block folders exist; 185 are scanned (helpers such as `updated-at`, `pgtap`, `rls-guard`, `saas` and `workflow-sdk` are left out).
- Capabilities come from a static scan of method names in each block's TypeScript files, so a count is indicative. A block that offers a capability under an unusual name shows as missing. Treat the matrix as a list of places to look.
- The example findings from all worktrees `../bsb-example-p*` were read. Every id on those branches is on the integration branch except EX-100 to EX-108 and EX-700 to EX-706 (search, command center and finance), which still wait for their own PRs.
- Not checked: runtime behaviour, SQL policy bodies, the MCP mapping per block (EX-1269), the pgTAP content, the docs pages one by one, and the screens still marked `later(...)`.

## What the example proved

The example covers about 120 blocks on a screen. The same four gaps repeated on every page, and each page paid for them with app code:

| Gap                                                                              | Pages that hit it                                                                                                                                                  | App code that fills it                                                                                        |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| Block lists return arrays, with no keyset, sort, facets or multi-value filters   | risks, leave, employees, onboarding, deadlines, deals, pipelines, segments, assets, leases, passes, donations, warranty, reviews, collections, checkout, workflows | `block-list.ts`, `block-status-list.ts`, `array-list.ts`, `simple-list.ts`, `admin-list.ts`, finance registry |
| Permission keys are not generated with a block                                   | leave, deadlines, commissions, referrals, periods, commerce, admin pages                                                                                           | one hand-written catalog migration per phase                                                                  |
| Errors name a hint code and no field                                             | passes, warranty, document templates, assets                                                                                                                       | `use-error-message.ts` and per-form checks                                                                    |
| Seeds, scale files, nav, coverage and route manifest are edited by hand per page | every page                                                                                                                                                         | five or six touched shared files per PR                                                                       |

## Capability matrix

By category first, then by block. A cell is `y` when the scan found the capability and `-` when it did not. Columns: List, Keyset (cursor or `page`), Get, Create, Update, Archive, Restore, Delete, Search, Count, Bulk, Export, Import, Idem (idempotency key), Lock (expected version), Events (events module), Bind (record binding).

### By category

| Category      | Blocks | List | Keyset | Get | Create | Update | Archive | Restore | Delete | Search | Count | Bulk | Export | Import | Idem | Lock | Events | Bind |
| ------------- | ------ | ---- | ------ | --- | ------ | ------ | ------- | ------- | ------ | ------ | ----- | ---- | ------ | ------ | ---- | ---- | ------ | ---- |
| admin         | 7      | 4    | 1      | 2   | 6      | 3      | 1       | 1       | 2      | 1      | 2     | 2    | 4      | 1      | 2    | 0    | 5      | 4    |
| ai            | 12     | 9    | 2      | 10  | 11     | 7      | 0       | 1       | 9      | 4      | 2     | 6    | 1      | 0      | 1    | 3    | 4      | 3    |
| automation    | 7      | 5    | 3      | 5   | 6      | 6      | 1       | 0       | 6      | 0      | 1     | 3    | 0      | 0      | 4    | 0    | 4      | 3    |
| collaboration | 13     | 9    | 3      | 6   | 13     | 9      | 3       | 2       | 5      | 1      | 3     | 0    | 0      | 0      | 0    | 0    | 10     | 8    |
| commerce      | 30     | 17   | 7      | 4   | 30     | 16     | 7       | 1       | 2      | 2      | 10    | 3    | 1      | 1      | 7    | 0    | 25     | 7    |
| content       | 10     | 7    | 3      | 6   | 10     | 4      | 4       | 1       | 3      | 2      | 1     | 3    | 0      | 0      | 1    | 0    | 8      | 2    |
| crm           | 14     | 7    | 2      | 7   | 14     | 7      | 1       | 1       | 4      | 2      | 4     | 1    | 0      | 0      | 0    | 0    | 10     | 2    |
| database      | 7      | 3    | 0      | 2   | 6      | 3      | 2       | 2       | 2      | 0      | 2     | 3    | 0      | 1      | 0    | 0    | 5      | 3    |
| developer     | 8      | 4    | 0      | 1   | 7      | 4      | 0       | 0       | 5      | 0      | 0     | 1    | 0      | 0      | 1    | 0    | 8      | 1    |
| growth        | 5      | 3    | 0      | 0   | 5      | 2      | 0       | 1       | 2      | 0      | 0     | 0    | 0      | 0      | 0    | 0    | 4      | 1    |
| identity      | 8      | 7    | 1      | 3   | 6      | 2      | 1       | 0       | 2      | 0      | 3     | 1    | 0      | 0      | 0    | 1    | 3      | 2    |
| messaging     | 3      | 2    | 2      | 2   | 3      | 3      | 0       | 1       | 2      | 2      | 2     | 2    | 0      | 0      | 2    | 0    | 3      | 1    |
| people        | 17     | 7    | 0      | 4   | 17     | 7      | 6       | 1       | 3      | 1      | 1     | 2    | 1      | 1      | 1    | 0    | 13     | 4    |
| scheduling    | 6      | 4    | 1      | 2   | 6      | 2      | 1       | 0       | 2      | 0      | 1     | 0    | 1      | 1      | 0    | 0    | 4      | 1    |
| tenancy       | 8      | 4    | 0      | 2   | 7      | 7      | 2       | 2       | 3      | 0      | 1     | 0    | 0      | 0      | 0    | 0    | 6      | 1    |
| work          | 30     | 21   | 7      | 9   | 30     | 18     | 8       | 2       | 6      | 5      | 4     | 3    | 0      | 1      | 0    | 0    | 25     | 7    |

Reading the totals across 185 blocks: 113 list, 32 page by keyset, 65 have a get, 37 archive but only 16 restore, 58 delete, 20 search, 8 export, 6 import, 19 take an idempotency key and 4 take an expected version. Every capability beyond create is partial, and the partial blocks are not the same ones from one capability to the next. The proposed fix is to declare the capabilities in the manifest (see refactor 1) so the matrix is checked, not scanned.

### By block

| Block                     | Category      | List | Keyset | Get | Create | Update | Archive | Restore | Delete | Search | Count | Bulk | Export | Import | Idem | Lock | Events | Bind |
| ------------------------- | ------------- | ---- | ------ | --- | ------ | ------ | ------- | ------- | ------ | ------ | ----- | ---- | ------ | ------ | ---- | ---- | ------ | ---- |
| audit                     | admin         | y    | y      | y   | y      | y      | -       | -       | y      | y      | y     | y    | y      | -      | y    | -    | y      | y    |
| compliance                | admin         | y    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | y      | y      | -    | -    | y      | -    |
| consents                  | admin         | y    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| data-lifecycle            | admin         | y    | -      | -   | y      | y      | y       | y       | y      | -      | -     | y    | y      | -      | -    | -    | y      | y    |
| governance                | admin         | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | y      | -      | y    | -    | -      | y    |
| impersonation             | admin         | -    | -      | -   | -      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| metrics                   | admin         | -    | -      | y   | y      | y      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | -      | -    |
| agents                    | ai            | y    | -      | y   | y      | y      | -       | -       | y      | y      | -     | -    | -      | -      | -    | y    | y      | -    |
| ai-cache                  | ai            | -    | -      | y   | y      | -      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| ai-chat                   | ai            | y    | y      | y   | y      | y      | -       | -       | y      | y      | -     | y    | -      | -      | y    | -    | y      | y    |
| ai-evals                  | ai            | y    | -      | y   | y      | -      | -       | -       | -      | -      | -     | -    | y      | -      | -    | -    | -      | y    |
| ai-files                  | ai            | y    | -      | y   | y      | y      | -       | -       | y      | -      | -     | y    | -      | -      | -    | y    | -      | -    |
| ai-guardrails             | ai            | y    | -      | y   | y      | -      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| ai-keys                   | ai            | y    | y      | y   | y      | y      | -       | -       | y      | -      | y     | y    | -      | -      | -    | -    | y      | y    |
| ai-schedules              | ai            | y    | -      | -   | y      | y      | -       | -       | y      | -      | -     | y    | -      | -      | -    | -    | -      | -    |
| knowledge                 | ai            | y    | -      | y   | y      | y      | -       | -       | y      | y      | y     | y    | -      | -      | -    | -    | -      | -    |
| memory                    | ai            | y    | -      | y   | y      | -      | -       | y       | y      | y      | -     | y    | -      | -      | -    | y    | -      | -    |
| prompts                   | ai            | -    | -      | y   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| vector-search             | ai            | -    | -      | -   | -      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| automations               | automation    | y    | -      | y   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | y    | -    | y      | -    |
| connectors                | automation    | y    | -      | y   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| outbox                    | automation    | -    | y      | -   | y      | y      | -       | -       | y      | -      | -     | y    | -      | -      | -    | -    | -      | -    |
| queue                     | automation    | y    | y      | y   | y      | y      | -       | -       | y      | -      | y     | y    | -      | -      | y    | -    | -      | -    |
| streams                   | automation    | -    | -      | -   | -      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| workflow-editor           | automation    | y    | -      | y   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | y    | -    | y      | y    |
| workflows                 | automation    | y    | y      | y   | y      | y      | y       | -       | y      | -      | -     | y    | -      | -      | y    | -    | y      | y    |
| acknowledgements          | collaboration | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| attachments               | collaboration | y    | -      | y   | y      | y      | -       | y       | y      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| channels                  | collaboration | y    | -      | y   | y      | y      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| collaboration             | collaboration | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | y    |
| comments                  | collaboration | y    | y      | y   | y      | y      | -       | y       | y      | -      | y     | -    | -      | -      | -    | -    | -      | y    |
| guests                    | collaboration | y    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| meetings                  | collaboration | y    | -      | y   | y      | y      | y       | -       | y      | y      | -     | -    | -      | -      | -    | -    | y      | -    |
| messaging                 | collaboration | y    | y      | y   | y      | y      | y       | -       | y      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| moderation                | collaboration | -    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| posts                     | collaboration | y    | -      | y   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| reactions                 | collaboration | -    | -      | -   | y      | y      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | y    |
| share-links               | collaboration | y    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| timeline                  | collaboration | y    | y      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| accounting                | commerce      | -    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| agent-checkout            | commerce      | y    | y      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | y    | -    | y      | -    |
| banking                   | commerce      | y    | -      | -   | y      | -      | -       | -       | -      | -      | y     | y    | y      | y      | -    | -    | y      | -    |
| billable-time             | commerce      | y    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| billing                   | commerce      | -    | y      | -   | y      | y      | y       | -       | -      | -      | y     | -    | -      | -      | y    | -    | y      | -    |
| catalog                   | commerce      | y    | y      | -   | y      | y      | -       | -       | -      | y      | -     | -    | -      | -      | -    | -    | y      | -    |
| commerce                  | commerce      | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| commissions               | commerce      | y    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| donations                 | commerce      | -    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | y    | -    | y      | y    |
| entitlements              | commerce      | -    | -      | y   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| expenses                  | commerce      | y    | -      | y   | y      | y      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| finance                   | commerce      | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| funding                   | commerce      | -    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| inventory                 | commerce      | y    | -      | -   | y      | y      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| invoices                  | commerce      | y    | -      | -   | y      | y      | y       | -       | y      | y      | -     | -    | -      | -      | -    | -    | y      | -    |
| leases                    | commerce      | y    | -      | y   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| ledger                    | commerce      | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | y    | -    | y      | y    |
| manufacturing             | commerce      | y    | -      | -   | y      | y      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| orders                    | commerce      | -    | -      | -   | y      | y      | -       | -       | -      | -      | y     | -    | -      | -      | y    | -    | y      | y    |
| periods                   | commerce      | y    | -      | -   | y      | -      | y       | y       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| procurement               | commerce      | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | y    | -      | -      | -    | -    | -      | -    |
| promotions                | commerce      | -    | -      | -   | y      | y      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| referrals                 | commerce      | y    | -      | -   | y      | -      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| reviews                   | commerce      | y    | -      | -   | y      | -      | -       | -       | y      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| rfqs                      | commerce      | y    | y      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| shipments                 | commerce      | y    | -      | y   | y      | y      | y       | -       | -      | -      | y     | -    | -      | -      | y    | -    | y      | y    |
| tax                       | commerce      | -    | -      | -   | y      | -      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| tills                     | commerce      | y    | y      | -   | y      | -      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| usage                     | commerce      | -    | y      | -   | y      | y      | -       | -       | -      | -      | -     | y    | -      | -      | y    | -    | -      | y    |
| warehouse                 | commerce      | y    | y      | -   | y      | y      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| cms                       | content       | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| content                   | content       | y    | -      | y   | y      | y      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| courses                   | content       | y    | -      | -   | y      | -      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| dam                       | content       | y    | y      | y   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| documents                 | content       | -    | y      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| drive                     | content       | y    | y      | y   | y      | -      | y       | y       | y      | y      | y     | y    | -      | -      | -    | -    | y      | y    |
| filespace                 | content       | -    | -      | -   | y      | -      | y       | -       | -      | y      | -     | y    | -      | -      | -    | -    | -      | -    |
| forms                     | content       | y    | -      | y   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| signatures                | content       | y    | -      | y   | y      | -      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| templates                 | content       | y    | -      | y   | y      | y      | -       | -       | y      | -      | -     | y    | -      | -      | y    | -    | y      | -    |
| activities                | crm           | -    | -      | y   | y      | y      | -       | -       | y      | -      | -     | y    | -      | -      | -    | -    | y      | -    |
| contacts                  | crm           | y    | y      | -   | y      | y      | -       | -       | -      | y      | y     | -    | -      | -      | -    | -    | y      | -    |
| contracts                 | crm           | y    | -      | y   | y      | y      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | y    |
| crm                       | crm           | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| deals                     | crm           | y    | -      | -   | y      | y      | y       | y       | y      | y      | -     | -    | -      | -      | -    | -    | y      | -    |
| enrichment                | crm           | -    | -      | y   | y      | -      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| forecasts                 | crm           | y    | -      | y   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| goals                     | crm           | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| lead-scoring              | crm           | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | y    |
| mail-sync                 | crm           | y    | y      | y   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| quotes                    | crm           | -    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| sales                     | crm           | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| segments                  | crm           | y    | -      | y   | y      | -      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| sequences                 | crm           | y    | -      | y   | y      | -      | -       | -       | y      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| field-encryption          | database      | -    | -      | -   | -      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| field-history             | database      | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | y    |
| imports                   | database      | y    | -      | y   | y      | y      | y       | -       | -      | -      | y     | y    | -      | y      | -    | -    | y      | y    |
| numbering                 | database      | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| rank                      | database      | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| trash                     | database      | y    | -      | -   | y      | y      | y       | y       | y      | -      | y     | y    | -      | -      | -    | -    | y      | -    |
| versions                  | database      | y    | -      | y   | y      | y      | -       | y       | y      | -      | -     | y    | -      | -      | -    | -    | y      | y    |
| api-keys                  | developer     | y    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| credentials               | developer     | -    | -      | -   | -      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| oauth-server              | developer     | y    | -      | -   | y      | -      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| security-events           | developer     | -    | -      | y   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| service-accounts          | developer     | y    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| signing-keys              | developer     | -    | -      | -   | y      | -      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| vercel-marketplace        | developer     | -    | -      | -   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| webhooks                  | developer     | y    | -      | -   | y      | y      | -       | -       | y      | -      | -     | y    | -      | -      | y    | -    | y      | y    |
| announcements             | growth        | y    | -      | -   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| flags                     | growth        | y    | -      | -   | y      | y      | -       | y       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| onboarding                | growth        | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| scores                    | growth        | y    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| waitlist                  | growth        | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| access-requests           | identity      | y    | -      | y   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| grants                    | identity      | -    | -      | -   | -      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| identities                | identity      | y    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| mfa                       | identity      | y    | -      | -   | -      | -      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| permissions               | identity      | y    | -      | y   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| sessions                  | identity      | y    | -      | -   | y      | -      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | -      | -    |
| sso                       | identity      | y    | -      | y   | y      | y      | -       | -       | y      | -      | y     | y    | -      | -      | -    | y    | y      | y    |
| subjects                  | identity      | y    | y      | -   | y      | -      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | y    |
| inbox                     | messaging     | y    | y      | y   | y      | y      | -       | y       | y      | y      | y     | y    | -      | -      | -    | -    | y      | y    |
| notifications             | messaging     | y    | y      | y   | y      | y      | -       | -       | y      | y      | y     | y    | -      | -      | y    | -    | y      | -    |
| push                      | messaging     | -    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | y    | -    | y      | -    |
| care                      | people        | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| care-plans                | people        | y    | -      | y   | y      | y      | y       | -       | -      | -      | -     | y    | -      | -      | -    | -    | y      | -    |
| clinical-decision-support | people        | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| e-prescribing             | people        | y    | -      | y   | y      | -      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| employees                 | people        | -    | -      | -   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| enrollments               | people        | y    | -      | -   | y      | y      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| hiring                    | people        | -    | -      | -   | y      | -      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| learning                  | people        | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| leave                     | people        | y    | -      | -   | y      | y      | y       | -       | -      | -      | -     | -    | -      | -      | y    | -    | y      | -    |
| medications               | people        | -    | -      | y   | y      | y      | -       | -       | -      | y      | -     | -    | -      | y      | -    | -    | y      | -    |
| observations              | people        | y    | -      | -   | y      | -      | -       | -       | -      | -      | y     | y    | -      | -      | -    | -    | y      | y    |
| payroll-export            | people        | y    | -      | y   | y      | -      | -       | -       | y      | -      | -     | -    | y      | -      | -    | -    | y      | -    |
| people                    | people        | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| qualifications            | people        | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| recruiting                | people        | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| shifts                    | people        | -    | -      | -   | y      | y      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| time-entries              | people        | y    | -      | -   | y      | y      | -       | y       | y      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| bookings                  | scheduling    | y    | y      | -   | y      | y      | y       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| calendar                  | scheduling    | y    | -      | y   | y      | y      | -       | -       | y      | -      | -     | -    | y      | y      | -    | -    | y      | -    |
| events                    | scheduling    | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| passes                    | scheduling    | y    | -      | y   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| reminders                 | scheduling    | y    | -      | -   | y      | -      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| scheduling                | scheduling    | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| document-templates        | tenancy       | y    | -      | -   | y      | y      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| domains                   | tenancy       | y    | -      | -   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| legal-entities            | tenancy       | y    | -      | y   | y      | y      | y       | y       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| memberships               | tenancy       | -    | -      | -   | -      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| organizations             | tenancy       | -    | -      | -   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| profiles                  | tenancy       | -    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| settings                  | tenancy       | -    | -      | y   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| teams                     | tenancy       | y    | -      | -   | y      | y      | y       | y       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| advisories                | work          | y    | -      | y   | y      | -      | -       | -       | -      | -      | -     | -    | -      | y      | -    | -    | y      | -    |
| appraisals                | work          | y    | y      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| approvals                 | work          | y    | -      | y   | y      | y      | y       | -       | -      | -      | -     | y    | -      | -      | -    | -    | y      | -    |
| assets                    | work          | y    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| assignment                | work          | -    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| bulk-actions              | work          | -    | -      | y   | y      | -      | -       | -       | y      | -      | -     | y    | -      | -      | -    | -    | y      | -    |
| cases                     | work          | y    | y      | y   | y      | y      | y       | y       | -      | y      | y     | -    | -      | -      | -    | -    | y      | -    |
| collections               | work          | y    | y      | -   | y      | -      | y       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| custom-fields             | work          | y    | -      | -   | y      | y      | -       | -       | -      | -      | -     | y    | -      | -      | -    | -    | y      | y    |
| deadlines                 | work          | y    | -      | -   | y      | -      | -       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| dispatch                  | work          | y    | -      | y   | y      | y      | y       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| incidents                 | work          | y    | -      | y   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| inspections               | work          | y    | -      | y   | y      | y      | y       | -       | -      | y      | -     | -    | -      | -      | -    | -    | y      | -    |
| lims                      | work          | y    | y      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| maintenance               | work          | y    | y      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| option-sets               | work          | y    | -      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| pipelines                 | work          | y    | -      | -   | y      | y      | y       | -       | -      | -      | y     | -    | -      | -      | -    | -    | y      | -    |
| projects                  | work          | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| relations                 | work          | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| risks                     | work          | y    | y      | y   | y      | y      | y       | -       | -      | y      | y     | -    | -      | -      | -    | -    | y      | -    |
| saved-views               | work          | y    | -      | -   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| search                    | work          | y    | -      | -   | y      | y      | -       | -       | y      | y      | -     | -    | -      | -      | -    | -    | -      | -    |
| service                   | work          | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| sla                       | work          | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| state-machine             | work          | -    | y      | -   | y      | y      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |
| support                   | work          | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| tags                      | work          | y    | -      | -   | y      | y      | -       | -       | y      | -      | -     | -    | -      | -      | -    | -    | y      | y    |
| tasks                     | work          | y    | -      | y   | y      | y      | y       | y       | y      | y      | -     | -    | -      | -      | -    | -    | y      | y    |
| undo                      | work          | -    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | -      | -    |
| warranty                  | work          | y    | -      | -   | y      | -      | -       | -       | -      | -      | -     | -    | -      | -      | -    | -    | y      | -    |

## Gaps by area

### Method surface

- Lists. 86 blocks that list return an array with no cursor. Ten blocks page (`agent-checkout`, `appraisals`, `dam`, `lims`, `maintenance`, `rfqs`, `risks`, `sso`, `tills`, `warehouse`), and each does so with its own option names. EX-1200, EX-1203.
- Sort and facets. Five blocks mention a sort and none returns facet counts, so the record list kit shows chips with no numbers on a block list (EX-1010 hand-writes the facet values). EX-1201, EX-1202.
- Search and count. Search is a method on 20 blocks; count on 37. App tables get exact or estimated counts (ADR 0425, 0433) and blocks do not. EX-1204, EX-1205.
- Lifecycle. The soft delete column `archived_at` is the convention (ADR 0346), yet 47 blocks delete with no archive and 28 archive with no restore. EX-1206, EX-1207.
- Writes. Bulk has three shapes, idempotency is on 19 blocks, expected-version locking on fewer than ten, and optimistic handlers on none of the controllers. EX-1209, EX-1212, EX-1213, EX-1214.
- Export and import are on 8 and 6 blocks. EX-1210, EX-1211.

### Names, types, events and errors

- Events. 137 blocks have an events module. Verbs drift: `deleted` 52 kinds, `archived` 16, `restored` 4, `cancelled` 18, `voided` 3, plus `closed`, `withdrawn`, `revoked`. EX-1230.
- Permission keys. `read` and `manage` dominate; `write`, `create`, `update`, `delete`, `assign`, `approve`, `publish` appear ad hoc. EX-1231. Keys are not generated with the block, which caused 403 pages in leave, deadlines, commissions, referrals, periods and the admin pages. EX-1232 (EX-807).
- Hint codes. 13 of 162 catalogs use a prefix other than the block name (`EVAL_`, `HOSTNAME_`, `ORGANIZATION_`, `CREDENTIAL_` and others). EX-1233. One block has up to four names across source, hints and the coverage map. EX-1234.
- `DbError`. The kinds are stable and serializable. A block error has a `hint` and a message, and no field list or per-code message, so forms show a generic line. EX-1235, EX-1236.
- Clients, hooks, controllers. 33 blocks have a `client.ts`; typed controller files exist for two. Record bindings are on 50 blocks and missing on invoices, quotes, deals, risks, employees, leave, expenses and bookings. EX-1237, EX-1238.

### Docs, skills and tests

Every block folder has a docs page. The consumer skill has seven reference files and none per block family. Scale files number 23 for about 190 blocks, and no list scale file exists yet. EX-1350, EX-1351, EX-1265.

## Generators

What exists today: `gen` renders the typed client, the model types, the block server modules, hooks names, projection reads and the SQL; `spec` renders the API description; the `create` core designs tables; the example has a route manifest and a generated `expectInstant` case per instant page.

| Output                            | Generated today                         | Missing, and where the app wrote it                      |
| --------------------------------- | --------------------------------------- | -------------------------------------------------------- |
| List query per entity             | no (EX-002)                             | `defineListQuery` by hand per table; block lists by hand |
| List route                        | no                                      | `/api/<entity>/list` per page                            |
| Columns and detail page           | no                                      | `features/<area>/*-columns.tsx`, detail pages per phase  |
| Forms                             | no                                      | action forms; schemas drift (EX-806)                     |
| Permission keys and role defaults | no (EX-807)                             | catalog migrations per phase                             |
| Seed data                         | declared defaults only (ADR 0205, 0440) | `seed.sql` rows per phase                                |
| pgTAP scale files                 | no                                      | 23 files, none per list                                  |
| API routes                        | spec yes, routes no                     | per-page handlers                                        |
| MCP tools                         | not verified                            | n/a                                                      |
| Search registration               | partly (EX-100 fixed, EX-101 open)      | `names.<entity>.url` and per-module fixes                |
| Nav items                         | no                                      | `nav-items.ts`                                           |
| Coverage entries                  | no                                      | `block-coverage.ts` (246 entries)                        |
| Messages                          | extraction only (EX-052)                | empty `msgstr` fixed by hand                             |

### One generator over the composable pieces

A page descriptor per entity, written once and read by every generator:

```ts
export const risks = defineEntityPage({
  entity: "risks.risk", // block entity: gives schema, sorts, facets, search, permissions
  route: "/risks",
  area: "compliance", // nav area
  columns: ["title", "category", "band", "residual"],
  sections: ["comments", "attachments", "versions", "timeline"],
  seed: { demo: 12, tiers: ["S", "M", "L"] },
});
```

From that one file `gen` would emit: the list query and its index, the list route and its schema, the column and detail components, the create and edit forms from the input schema, the permission keys and role defaults, the seed rows, `scale_list_<entity>.test.sql`, the nav item, the route manifest entry, the coverage entry, the message keys and the MCP tool names. The block manifest supplies the entity's `sorts`, `facets`, `search`, `mutability`, `permissions` and `personalData`, so the descriptor stays under ten lines. The first slice to build is the list query plus route, because it removes five app helpers (EX-1294).

## Composition and shared cores

- Recurrence. The expander shipped at `better-supabase/recurrence` and ADR 0197 still calls it planned. Calendar, reminders, tasks and templates use it; bookings and maintenance carry their own. EX-1290.
- Periods, money, digests. `periods` is a block, digests live only in notifications, and 39 blocks handle money separately. EX-1291.
- Declared composition (ADR 0196). Manifests declare `sections` in 1 block, `automations` in 4 and `composite` in 19; `links` and `concerns` live in SQL `NAMES` only. EX-1292. ADR 0064 names a `flows` subpath that does not exist. EX-1293.
- Parties and subject labels. Contacts, people, employees, identities and profiles each model a person, and subject references have no label. EX-1295, EX-1296.
- Hand-rolled glue in the app. `lib/block-list.ts`, `block-status-list.ts`, `array-list.ts`, `simple-list.ts`, `admin-list.ts`, the finance registry (EX-700), the facet merge in EX-802 and EX-812, and the keyset helper in EX-901. All disappear with one `page` contract. EX-1294.

## Edge case coverage

Status per concern across the catalog. "Covered" means a block or core feature handles it and the example shows it; "partial" means some blocks do; "missing" means no declared support.

| Concern                          | Status  | Where it exists                                                   | Where it is missing                                      | Rows                      |
| -------------------------------- | ------- | ----------------------------------------------------------------- | -------------------------------------------------------- | ------------------------- |
| Multi-tenant isolation           | covered | tenant policies on block tables (ADR 0099, 0426), tested in pgTAP | none found                                               | none                      |
| Roles and per-record access      | partial | permissions block, record teams (ADR 0134), grants                | no per-entity declaration, keys not generated            | EX-1231, EX-1232, EX-1322 |
| Soft delete and restore          | partial | tasks, deals, cases, drive, teams, trash                          | 47 blocks hard delete, 28 archive without restore        | EX-1206, EX-1207          |
| Audit trail                      | covered | audit block and row triggers (ADR 0196, 0252)                     | impersonation actor outside audit                        | EX-1321                   |
| Versioning                       | partial | versions, field-history, 77 mentions                              | no declaration per entity                                | EX-1323                   |
| Idempotency                      | partial | 19 blocks and the idempotency block                               | tasks, deals, quotes and most creates                    | EX-1212                   |
| Webhooks in and out              | covered | webhooks, webhook inbox, outbox                                   | no public event flag                                     | EX-1320                   |
| Rate limits and quotas           | partial | rate-limit, usage, about 18 blocks                                | option names differ                                      | EX-1313                   |
| Usage metering and billing       | partial | usage, billing, entitlements                                      | methods do not declare meters                            | EX-1314                   |
| Trials and plan limits           | partial | billing, entitlements                                             | no limit check before create                             | EX-1312                   |
| Invitations, SSO, SCIM           | partial | memberships, sso                                                  | invitation list page contract                            | EX-1329                   |
| GDPR export and erasure          | partial | 18 blocks mention it                                              | no cross-block flow                                      | EX-1310                   |
| Retention and legal hold         | partial | data-lifecycle, drive, audit                                      | other entities                                           | EX-1311                   |
| Time zones and recurrence        | partial | calendar, reminders, tasks, templates                             | bookings, maintenance own rules                          | EX-1290, EX-1315          |
| Currencies and tax               | partial | money codec, tax block, 39 blocks                                 | list and export formatting                               | EX-1316                   |
| Locale and i18n                  | partial | next-intl in the example                                          | block messages English only                              | EX-1236, EX-1317          |
| Attachments                      | covered | attachments with document types                                   | detail pages of blocks without a binding wire it by hand | EX-1237                   |
| Comments and mentions            | covered | comments, messaging                                               | record binding gaps                                      | EX-1237                   |
| Notifications                    | covered | notifications, digests                                            | digest helper not shared                                 | EX-1291                   |
| Search                           | partial | search block, 20 methods                                          | `q` option on lists, override of columns                 | EX-1204, EX-1266          |
| Import and export                | partial | imports, 8 and 6 blocks                                           | no `export` or `importTarget` contract                   | EX-1210, EX-1211          |
| Offline sync                     | partial | PowerSync streams from views                                      | per-block declaration                                    | EX-1318                   |
| Realtime                         | partial | realtime-tables, controllers                                      | no per-entity flag, hooks do not subscribe               | EX-1319                   |
| API keys and OAuth apps          | covered | api-keys, oauth-server, pages                                     | scopes not generated                                     | EX-1330                   |
| Impersonation                    | partial | impersonation block                                               | actor not recorded on writes                             | EX-1321                   |
| Feature flags                    | partial | flags block                                                       | no entity flag declaration                               | EX-1328                   |
| Concurrency (optimistic locking) | missing | fewer than ten blocks                                             | the rest                                                 | EX-1213                   |
| Bulk operations at scale         | partial | 30 blocks, bulk-actions                                           | shapes differ, limit not declared                        | EX-1209                   |
| Long-running jobs                | partial | queue in about 20 blocks                                          | no common progress shape                                 | EX-1324                   |
| Archival and partitioning        | partial | audit, outbox, notifications                                      | entity tables                                            | EX-1325                   |
| Empty, loading, error states     | partial | record list kit                                                   | block hooks return raw results                           | EX-1326                   |
| Accessibility                    | partial | ReUI components                                                   | no automated pass over generated pages                   | EX-1327                   |

## Prioritized refactor list

Breaking changes are allowed. Order is by how many pages and generators each change unblocks.

1. One declared entity surface in the manifest: `entities: { risk: { sorts, facets, search, mutability, permissions, personalData, retention, realtime, offline } }`. The matrix, the generators and the checks read it. (EX-1208, EX-1232, EX-1352)
2. One list contract: `page({ q, sort, filters, after, limit })` returning `ListPage`, with array filters and `{ value, exact }` counts. Rename `list` to a capped helper on top of it. (EX-1200 to EX-1205)
3. `facets(options)` with counts on the same contract. (EX-1202)
4. Keys generated from the manifest: `<block>.<entity>.<verb>` with the fixed verb set `read`, `create`, `update`, `archive`, `delete`, `export`, `import`, `manage`. (EX-1231, EX-1232)
5. Soft delete by default: every record entity gets `archive` and `restore`, and `delete` becomes `purge` behind its own key. Events use `archived` and `restored`. (EX-1206, EX-1207, EX-1230)
6. `expectedVersion` on every update and a `STALE_WRITE` conflict error, with optimistic handlers in the controllers. (EX-1213, EX-1214)
7. `idempotencyKey` on every create and action. (EX-1212)
8. Field-aware errors: `invalid_input` carries `fields: [{ path, code, message }]`, and the catalog ships default messages and next-intl keys. (EX-1235, EX-1236)
9. The page descriptor and generator described above, starting with the list query, route and scale file. (EX-1260 to EX-1268, EX-1294)
10. `bulk(ids, action)` with one result shape and a declared limit. (EX-1209)
11. `export(options)` and `importTarget` over the list contract. (EX-1210, EX-1211)
12. Hint codes and block keys derived from one name; add the checks. (EX-1233, EX-1234)
13. Move bookings and maintenance onto `better-supabase/recurrence`, extract the digest and money helpers, and update ADR 0197. (EX-1290, EX-1291)
14. A `subjects.label(refs)` batch lookup and a `party` core. (EX-1295, EX-1296)
15. Cross-block `personalData` export and erase, with retention classes. (EX-1310, EX-1311)
16. Plan limit and meter declarations on methods. (EX-1312, EX-1314)
17. Record bindings for invoices, quotes, deals, risks, employees, leave, expenses and bookings. (EX-1237)
18. Generate the capability matrix and the per-category skill references from the manifests. (EX-1350, EX-1352)

## Proposed ADR titles

1. Declare each entity's sorts, facets, search and mutability in the block manifest.
2. One `page` contract for every block list, with facets and counts.
3. Soft delete by default, `purge` for hard delete, and the event verb vocabulary.
4. Permission keys per entity and verb, generated from the manifest.
5. Optimistic locking with `expectedVersion` and `STALE_WRITE`.
6. Field-aware `DbError` and a generated message catalog.
7. The entity page descriptor and the generators over it.
8. Bulk, export and import as list-contract verbs.
9. Name one block one key: source, hints, coverage and docs.
10. Ship recurrence, digest and money cores and retire the per-block copies (replaces 0197).
11. Personal data, retention and plan limits as manifest declarations.
