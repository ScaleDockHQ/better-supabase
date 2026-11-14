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

### Declared entity surface

The scanned tables above stay as the audit's baseline until lane P replaces them. This table is not scanned: `pnpm catalog` generates it from the `entities` of every block manifest (ADR 0689), and `pnpm catalog:check` fails when it is stale.

<!-- entity-matrix:start, written by `pnpm catalog`; do not edit by hand -->

Generated from the `entities` of every block manifest. `Emits` lists the methods that record an event and `No event` the mutating methods that record none (EX-1216). A `-` means the manifest does not declare the field yet.

| Category      | Blocks | Entities | editable | append-only | state-machine | read-only |
| ------------- | ------ | -------- | -------- | ----------- | ------------- | --------- |
| admin         | 7      | 14       | 5        | 1           | 7             | 1         |
| ai            | 12     | 13       | 5        | 3           | 1             | 4         |
| automation    | 11     | 11       | 3        | 2           | 1             | 5         |
| collaboration | 13     | 21       | 7        | 5           | 8             | 1         |
| commerce      | 30     | 86       | 30       | 9           | 30            | 17        |
| content       | 10     | 15       | 6        | 2           | 5             | 2         |
| crm           | 14     | 18       | 11       | 5           | 1             | 1         |
| database      | 13     | 13       | 0        | 2           | 5             | 6         |
| developer     | 9      | 11       | 6        | 0           | 5             | 0         |
| growth        | 5      | 5        | 3        | 1           | 1             | 0         |
| identity      | 9      | 14       | 3        | 0           | 5             | 6         |
| messaging     | 3      | 3        | 1        | 0           | 2             | 0         |
| people        | 17     | 37       | 17       | 6           | 13            | 1         |
| scheduling    | 6      | 8        | 3        | 1           | 2             | 2         |
| tenancy       | 10     | 15       | 9        | 1           | 1             | 4         |
| work          | 30     | 64       | 32       | 10          | 11            | 11        |

| Block                     | Category      | Entity                     | Mutability    | Emits                  | No event               | Sorts                                    | Facets                 | Search      | Realtime | Offline | Versioned |
| ------------------------- | ------------- | -------------------------- | ------------- | ---------------------- | ---------------------- | ---------------------------------------- | ---------------------- | ----------- | -------- | ------- | --------- |
| audit                     | admin         | audit                      | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| compliance                | admin         | control                    | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| compliance                | admin         | control_framework          | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| compliance                | admin         | evidence_task              | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| compliance                | admin         | compliance_policy          | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| consents                  | admin         | consent                    | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| consents                  | admin         | consent_purpose            | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| data-lifecycle            | admin         | data_export                | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| data-lifecycle            | admin         | organization               | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| data-lifecycle            | admin         | legal_hold                 | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| data-lifecycle            | admin         | data_subject_request       | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| governance                | admin         | governance                 | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| impersonation             | admin         | support_session            | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| metrics                   | admin         | metric                     | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| agents                    | ai            | agent                      | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| ai-cache                  | ai            | ai_cache                   | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| ai-chat                   | ai            | ai_chat                    | editable      | -                      | create, update, delete | -                                        | -                      | -           | -        | -       | -         |
| ai-chat                   | ai            | ai_project                 | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| ai-evals                  | ai            | ai_eval                    | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| ai-files                  | ai            | ai_document                | editable      | -                      | create, update, delete | -                                        | -                      | -           | -        | -       | -         |
| ai-guardrails             | ai            | guardrail                  | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| ai-keys                   | ai            | ai_provider_key            | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| ai-schedules              | ai            | ai_scheduled_task          | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| knowledge                 | ai            | knowledge_document         | append-only   | -                      | create, delete         | -                                        | -                      | -           | -        | -       | -         |
| memory                    | ai            | memory                     | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| prompts                   | ai            | prompt                     | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| vector-search             | ai            | vector_search              | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| automations               | automation    | automation                 | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| connectors                | automation    | connector_server           | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| idempotency               | automation    | idempotency                | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| outbox                    | automation    | outbox                     | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| queue                     | automation    | queue                      | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| rate-limit                | automation    | rate_limit                 | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| streams                   | automation    | stream                     | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| webhook-inbox             | automation    | webhook_inbox              | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| workflow-editor           | automation    | workflow_definition        | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| workflow-sdk              | automation    | workflow_sdk               | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| workflows                 | automation    | workflow_run               | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| acknowledgements          | collaboration | acknowledgement            | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| acknowledgements          | collaboration | acknowledgement_assignment | append-only   | create, delete         | -                      | -                                        | -                      | -           | -        | -       | -         |
| attachments               | collaboration | attachment                 | state-machine | -                      | create, delete         | -                                        | -                      | -           | -        | -       | -         |
| channels                  | collaboration | channel                    | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| collaboration             | collaboration | collaboration              | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| comments                  | collaboration | comment                    | append-only   | -                      | create, delete         | -                                        | -                      | -           | -        | -       | -         |
| guests                    | collaboration | guest                      | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| guests                    | collaboration | guest_grant                | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| meetings                  | collaboration | meeting                    | editable      | create, update, delete | -                      | startsAt, title                          | kind, status           | y           | -        | -       | -         |
| meetings                  | collaboration | meeting_attendee           | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| meetings                  | collaboration | meeting_agenda_item        | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| meetings                  | collaboration | meeting_decision           | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| meetings                  | collaboration | meeting_action_item        | append-only   | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| messaging                 | collaboration | message                    | editable      | delete                 | update                 | -                                        | -                      | -           | -        | -       | -         |
| messaging                 | collaboration | conversation               | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| moderation                | collaboration | moderation_item            | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| posts                     | collaboration | post_board                 | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| posts                     | collaboration | post                       | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| reactions                 | collaboration | reaction                   | append-only   | create, delete         | -                      | -                                        | -                      | -           | -        | -       | -         |
| share-links               | collaboration | share_link                 | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| timeline                  | collaboration | timeline_entry             | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| accounting                | commerce      | accounting_account         | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| accounting                | commerce      | accounting_journal         | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| accounting                | commerce      | accounting_period          | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| accounting                | commerce      | accounting_entry           | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| accounting                | commerce      | accounting_dimension       | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| accounting                | commerce      | accounting_budget          | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| agent-checkout            | commerce      | checkout_session           | editable      | create, update         | -                      | createdAt, expiresAt                     | status, protocol       | -           | -        | -       | -         |
| agent-checkout            | commerce      | agent_mandate              | state-machine | create                 | -                      | createdAt, expiresAt                     | status, vct            | -           | -        | -       | -         |
| banking                   | commerce      | bank_transaction           | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| banking                   | commerce      | bank_account               | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| banking                   | commerce      | bank_statement             | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| banking                   | commerce      | bank_match                 | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| banking                   | commerce      | bank_rule                  | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| billable-time             | commerce      | time_rate                  | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| billing                   | commerce      | billing                    | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| catalog                   | commerce      | product                    | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| catalog                   | commerce      | product_variant            | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| commerce                  | commerce      | commerce                   | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| commissions               | commerce      | commission_plan            | editable      | create, update         | -                      | createdAt, name                          | kind                   | -           | -        | -       | -         |
| commissions               | commerce      | commission_assignment      | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| commissions               | commerce      | commission                 | state-machine | -                      | -                      | occurredOn, createdAt, amount            | status, seller         | -           | -        | -       | -         |
| commissions               | commerce      | commission_statement       | state-machine | -                      | -                      | endsOn, createdAt, total                 | status, seller         | -           | -        | -       | -         |
| donations                 | commerce      | donation                   | state-machine | -                      | -                      | receivedOn, createdAt                    | status, fundId         | -           | -        | -       | -         |
| donations                 | commerce      | pledge                     | editable      | create, update         | -                      | createdAt                                | status                 | -           | -        | -       | -         |
| donations                 | commerce      | donation_fund              | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| donations                 | commerce      | donation_receipt           | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| entitlements              | commerce      | entitlement                | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| expenses                  | commerce      | expense_report             | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| expenses                  | commerce      | expense_line               | editable      | -                      | create, update, delete | -                                        | -                      | -           | -        | -       | -         |
| expenses                  | commerce      | expense_category           | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| finance                   | commerce      | finance                    | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| funding                   | commerce      | funding_product            | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| funding                   | commerce      | funding_award              | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| funding                   | commerce      | funding_delivery           | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| funding                   | commerce      | funding_claim              | state-machine | create, delete         | -                      | -                                        | -                      | -           | -        | -       | -         |
| funding                   | commerce      | funding_claim_line         | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| inventory                 | commerce      | inventory_location         | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| inventory                 | commerce      | purchase_order             | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| inventory                 | commerce      | purchase_requisition       | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| inventory                 | commerce      | inventory_receipt          | append-only   | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| invoices                  | commerce      | invoice                    | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| leases                    | commerce      | lease                      | state-machine | create                 | -                      | startsOn, endsOn, createdAt              | status, unitId         | -           | -        | -       | -         |
| ledger                    | commerce      | ledger_account             | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| ledger                    | commerce      | ledger_transaction         | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| ledger                    | commerce      | ledger_hold                | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| manufacturing             | commerce      | production_order           | state-machine | -                      | create                 | dueOn, createdAt, number                 | status                 | -           | -        | -       | -         |
| manufacturing             | commerce      | bom                        | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| manufacturing             | commerce      | bom_component              | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| manufacturing             | commerce      | bom_operation              | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| manufacturing             | commerce      | work_center                | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| manufacturing             | commerce      | production_order_operation | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| manufacturing             | commerce      | production_consumption     | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| manufacturing             | commerce      | stock_lot_link             | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| orders                    | commerce      | order                      | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| orders                    | commerce      | cart                       | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| periods                   | commerce      | period                     | state-machine | create                 | -                      | startsOn, endsOn                         | kind, status           | -           | -        | -       | -         |
| procurement               | commerce      | procurement                | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| promotions                | commerce      | promotion                  | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| referrals                 | commerce      | referral_code              | append-only   | create                 | -                      | createdAt                                | referrer               | -           | -        | -       | -         |
| referrals                 | commerce      | referral                   | state-machine | -                      | -                      | createdAt                                | status, referrer       | -           | -        | -       | -         |
| reviews                   | commerce      | review                     | state-machine | delete                 | create                 | -                                        | -                      | -           | -        | -       | -         |
| rfqs                      | commerce      | rfq                        | editable      | create, update         | -                      | number, dueAt                            | status                 | -           | -        | -       | -         |
| rfqs                      | commerce      | rfq_line                   | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| rfqs                      | commerce      | rfq_supplier               | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| rfqs                      | commerce      | rfq_quote                  | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| rfqs                      | commerce      | rfq_quote_line             | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| shipments                 | commerce      | shipment                   | state-machine | create                 | -                      | createdAt, deliveredAt                   | status, carrier        | -           | -        | -       | -         |
| shipments                 | commerce      | shipment_package           | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| shipments                 | commerce      | shipment_tracking_event    | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| shipments                 | commerce      | shipment_line              | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| tax                       | commerce      | tax_code                   | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| tax                       | commerce      | tax_rate                   | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| tax                       | commerce      | tax_return                 | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| tills                     | commerce      | till                       | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| tills                     | commerce      | till_session               | state-machine | -                      | create                 | openedAt, closedAt                       | status, tillId         | -           | -        | -       | -         |
| tills                     | commerce      | till_movement              | append-only   | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| tills                     | commerce      | till_count                 | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| tills                     | commerce      | till_deposit               | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| usage                     | commerce      | usage                      | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| warehouse                 | commerce      | pick_list                  | state-machine | create                 | -                      | createdAt, pickedAt                      | status, documentType   | -           | -        | -       | -         |
| warehouse                 | commerce      | pick_wave                  | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| warehouse                 | commerce      | pick_line                  | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| warehouse                 | commerce      | count_plan                 | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| warehouse                 | commerce      | putaway_rule               | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| warehouse                 | commerce      | bin_slot                   | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| warehouse                 | commerce      | variant_size               | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| cms                       | content       | cm                         | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| content                   | content       | content_entry              | editable      | create, update         | -                      | updatedAt, title, createdAt, publishedAt | type, locale, status   | title, slug | -        | -       | -         |
| courses                   | content       | course                     | editable      | create, update, delete | -                      | title                                    | status                 | -           | -        | -       | -         |
| courses                   | content       | course_module              | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| courses                   | content       | course_lesson              | editable      | -                      | create, update, delete | -                                        | -                      | -           | -        | -       | -         |
| courses                   | content       | course_certificate         | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| dam                       | content       | dam_usage_right            | state-machine | -                      | -                      | expiresOn, startsOn                      | status                 | -           | -        | -       | -         |
| dam                       | content       | dam_rendition              | append-only   | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| documents                 | content       | document                   | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| documents                 | content       | document_suggestion        | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| drive                     | content       | drive_node                 | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| filespace                 | content       | filespace                  | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| forms                     | content       | form                       | editable      | create                 | update                 | createdAt, title, key                    | status                 | -           | -        | -       | -         |
| signatures                | content       | signature_request          | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| templates                 | content       | template                   | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| activities                | crm           | activity                   | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| contacts                  | crm           | company                    | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| contacts                  | crm           | person                     | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| contracts                 | crm           | contract                   | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| contracts                 | crm           | contract_obligation        | editable      | create, update         | delete                 | -                                        | -                      | -           | -        | -       | -         |
| crm                       | crm           | crm                        | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| deals                     | crm           | deal                       | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| enrichment                | crm           | enrichment                 | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| forecasts                 | crm           | forecast_snapshot          | append-only   | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| goals                     | crm           | goal                       | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| lead-scoring              | crm           | lead_scoring               | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| mail-sync                 | crm           | mail_thread                | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| mail-sync                 | crm           | mail_account               | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| mail-sync                 | crm           | mail_message               | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| quotes                    | crm           | quote                      | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| sales                     | crm           | sale                       | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| segments                  | crm           | segment                    | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| sequences                 | crm           | sequence                   | editable      | create, update, delete | -                      | name, updatedAt                          | status                 | -           | -        | -       | -         |
| field-encryption          | database      | field_key                  | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| field-history             | database      | field_history              | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| imports                   | database      | import                     | state-machine | -                      | create                 | createdAt                                | source, status         | -           | -        | -       | -         |
| jsonb-schemas             | database      | jsonb_schema               | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| numbering                 | database      | number                     | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| pgtap                     | database      | pgtap                      | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| rank                      | database      | rank                       | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| read-sets                 | database      | read_set                   | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| realtime-tables           | database      | realtime_table             | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| rls-guard                 | database      | rls_guard                  | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| trash                     | database      | subject                    | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| updated-at                | database      | updated_at                 | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| versions                  | database      | version                    | state-machine | create, delete         | -                      | -                                        | -                      | -           | -        | -       | -         |
| api-keys                  | developer     | api_key                    | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| credentials               | developer     | credential                 | editable      | update, delete         | -                      | -                                        | -                      | -           | -        | -       | -         |
| incoming-webhooks         | developer     | incoming_webhook           | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| oauth-server              | developer     | oauth_client               | editable      | delete                 | update                 | -                                        | -                      | -           | -        | -       | -         |
| oauth-server              | developer     | oauth_grant                | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| security-events           | developer     | ssf_stream                 | editable      | create, delete         | update                 | -                                        | -                      | -           | -        | -       | -         |
| service-accounts          | developer     | service_principal          | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| signing-keys              | developer     | signing_key                | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| vercel-marketplace        | developer     | marketplace_installation   | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| vercel-marketplace        | developer     | marketplace_invoice        | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| webhooks                  | developer     | webhook_endpoint           | editable      | -                      | create, update, delete | -                                        | -                      | -           | -        | -       | -         |
| announcements             | growth        | announcement               | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| flags                     | growth        | flag                       | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| onboarding                | growth        | onboarding                 | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| scores                    | growth        | score_model                | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| waitlist                  | growth        | waitlist_entry             | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| access-requests           | identity      | access_request             | state-machine | -                      | -                      | createdAt                                | status, role           | -           | -        | -       | -         |
| created-by                | identity      | created_by                 | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| grants                    | identity      | grant                      | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| identities                | identity      | identity                   | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| mfa                       | identity      | mfa                        | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| permissions               | identity      | permission                 | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| sessions                  | identity      | session                    | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| sso                       | identity      | organization               | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| sso                       | identity      | sso_domain                 | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| sso                       | identity      | sso_provider               | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| sso                       | identity      | scim_user                  | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| sso                       | identity      | scim_group                 | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| subjects                  | identity      | subject_member             | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| subjects                  | identity      | subject                    | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| inbox                     | messaging     | inbox                      | editable      | -                      | create, update         | -                                        | -                      | -           | -        | -       | -         |
| notifications             | messaging     | notification               | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| push                      | messaging     | push                       | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| care                      | people        | care                       | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| care-plans                | people        | care_plan                  | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| care-plans                | people        | care_plan_problem          | editable      | -                      | create, update         | -                                        | -                      | -           | -        | -       | -         |
| care-plans                | people        | care_plan_goal             | editable      | -                      | create, update         | -                                        | -                      | -           | -        | -       | -         |
| care-plans                | people        | care_plan_action           | editable      | -                      | create, update         | -                                        | -                      | -           | -        | -       | -         |
| care-plans                | people        | care_plan_evaluation       | append-only   | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| clinical-decision-support | people        | care_alert                 | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| clinical-decision-support | people        | care_rule                  | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| e-prescribing             | people        | prescription               | state-machine | create                 | -                      | createdAt, signedAt                      | status                 | -           | -        | -       | -         |
| employees                 | people        | employee                   | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| enrollments               | people        | enrollment_program         | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| enrollments               | people        | enrollment                 | state-machine | create                 | -                      | updatedAt, enrolledAt                    | status, program        | -           | -        | -       | -         |
| hiring                    | people        | job_opening                | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| hiring                    | people        | application                | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| hiring                    | people        | interview                  | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| learning                  | people        | learning                   | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| leave                     | people        | leave_request              | editable      | update                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| leave                     | people        | leave_type                 | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| medications               | people        | medication                 | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| medications               | people        | medication_order           | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| medications               | people        | medication_administration  | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| observations              | people        | observation                | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| observations              | people        | observation_definition     | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| payroll-export            | people        | payroll_run                | state-machine | create                 | delete                 | periodFrom, createdAt                    | status                 | -           | -        | -       | -         |
| payroll-export            | people        | payroll_line               | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| people                    | people        | people                     | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| qualifications            | people        | qualification              | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| qualifications            | people        | qualification_type         | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| qualifications            | people        | qualification_requirement  | append-only   | -                      | create, delete         | -                                        | -                      | -           | -        | -       | -         |
| recruiting                | people        | recruiting                 | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| shifts                    | people        | shift                      | editable      | create                 | update                 | -                                        | -                      | -           | -        | -       | -         |
| shifts                    | people        | shift_template             | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| shifts                    | people        | shift_assignment           | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| shifts                    | people        | shift_swap                 | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| shifts                    | people        | shift_availability         | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| time-entries              | people        | time_entry                 | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| time-entries              | people        | timesheet                  | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| bookings                  | scheduling    | booking                    | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| calendar                  | scheduling    | calendar_event             | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| calendar                  | scheduling    | calendar                   | editable      | create, update         | delete                 | -                                        | -                      | -           | -        | -       | -         |
| events                    | scheduling    | event                      | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| passes                    | scheduling    | pass                       | state-machine | -                      | create                 | createdAt, validFrom, validUntil         | status                 | -           | -        | -       | -         |
| passes                    | scheduling    | pass_check_in              | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| reminders                 | scheduling    | reminder                   | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| scheduling                | scheduling    | scheduling                 | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| document-templates        | tenancy       | document_template          | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| document-templates        | tenancy       | document_text_block        | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| document-templates        | tenancy       | document_snapshot          | append-only   | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| domains                   | tenancy       | hostname                   | state-machine | create, delete         | -                      | hostname, createdAt                      | kind, verified         | -           | -        | -       | -         |
| legal-entities            | tenancy       | legal_entity               | editable      | create, update         | -                      | code, name                               | isDefault              | -           | -        | -       | -         |
| legal-entities            | tenancy       | legal_entity_setting       | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| memberships               | tenancy       | membership                 | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| organizations             | tenancy       | organization               | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| organizations             | tenancy       | invitation                 | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| profiles                  | tenancy       | profile                    | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| reserved-slugs            | tenancy       | reserved_slug              | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| saas                      | tenancy       | saa                        | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| settings                  | tenancy       | organization_setting       | editable      | update                 | create                 | -                                        | -                      | -           | -        | -       | -         |
| settings                  | tenancy       | platform_setting           | editable      | update                 | create                 | -                                        | -                      | -           | -        | -       | -         |
| teams                     | tenancy       | team                       | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| advisories                | work          | advisory                   | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| advisories                | work          | advisory_product           | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| advisories                | work          | advisory_product_version   | append-only   | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| advisories                | work          | sbom_component             | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| advisories                | work          | vulnerability              | editable      | create                 | update                 | -                                        | -                      | -           | -        | -       | -         |
| advisories                | work          | vex_statement              | editable      | update                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| advisories                | work          | advisory_vulnerability     | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| appraisals                | work          | appraisal                  | state-machine | create                 | -                      | createdAt, rating                        | status                 | -           | -        | -       | -         |
| appraisals                | work          | appraisal_cycle            | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| appraisals                | work          | appraisal_review           | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| appraisals                | work          | appraisal_calibration      | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| appraisals                | work          | appraisal_goal             | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| appraisals                | work          | appraisal_competency       | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| appraisals                | work          | appraisal_review_rating    | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| approvals                 | work          | approval                   | state-machine | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| assets                    | work          | asset                      | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| assets                    | work          | asset_location             | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| assignment                | work          | assignment_queue           | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| bulk-actions              | work          | bulk_run                   | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| cases                     | work          | case                       | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| cases                     | work          | case_kind                  | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| cases                     | work          | case_action                | append-only   | create, delete         | -                      | -                                        | -                      | -           | -        | -       | -         |
| collections               | work          | subject_collection         | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| custom-fields             | work          | field_definition           | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| deadlines                 | work          | deadline                   | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| dispatch                  | work          | work_order                 | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| dispatch                  | work          | dispatch_route             | state-machine | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| dispatch                  | work          | work_order_part            | append-only   | -                      | create, delete         | -                                        | -                      | -           | -        | -       | -         |
| incidents                 | work          | incident                   | editable      | update                 | create                 | -                                        | -                      | -           | -        | -       | -         |
| incidents                 | work          | status_component           | editable      | update                 | delete                 | -                                        | -                      | -           | -        | -       | -         |
| incidents                 | work          | incident_postmortem        | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| incidents                 | work          | status_page                | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| inspections               | work          | inspection                 | editable      | update                 | create                 | plannedStart, number                     | status, kind           | y           | -        | -       | -         |
| inspections               | work          | inspection_program         | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| inspections               | work          | inspection_finding         | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| inspections               | work          | inspection_member          | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| lims                      | work          | lims_sample                | state-machine | -                      | -                      | number, receivedOn                       | status, kind           | -           | -        | -       | -         |
| lims                      | work          | lims_method                | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| lims                      | work          | lims_result                | state-machine | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| maintenance               | work          | maintenance_plan           | editable      | create, update, delete | -                      | nextDueAt, title                         | status, kind           | -           | -        | -       | -         |
| maintenance               | work          | maintenance_plan_part      | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| maintenance               | work          | maintenance_meter          | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| maintenance               | work          | maintenance_meter_reading  | append-only   | create                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| maintenance               | work          | maintenance_calibration    | append-only   | create                 | -                      | performedAt, dueAt                       | result                 | -           | -        | -       | -         |
| option-sets               | work          | option_set                 | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| pipelines                 | work          | pipeline                   | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| projects                  | work          | project                    | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| relations                 | work          | relation                   | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| risks                     | work          | risk                       | editable      | create, update         | -                      | residualScore, number, nextReviewOn      | status, category, band | y           | -        | -       | -         |
| risks                     | work          | risk_matrix                | editable      | create, update         | -                      | -                                        | -                      | -           | -        | -       | -         |
| risks                     | work          | risk_assessment            | read-only     | -                      | -                      | -                                        | -                      | -           | -        | -       | -         |
| saved-views               | work          | saved_view                 | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| search                    | work          | search                     | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| service                   | work          | service                    | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| sla                       | work          | sla_policy                 | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| state-machine             | work          | status                     | editable      | update                 | -                      | -                                        | -                      | -           | -        | -       | -         |
| support                   | work          | support                    | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| tags                      | work          | tag                        | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| tasks                     | work          | task                       | editable      | create, update, delete | -                      | -                                        | -                      | -           | -        | -       | -         |
| tasks                     | work          | project                    | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| tasks                     | work          | iteration                  | editable      | -                      | update                 | -                                        | -                      | -           | -        | -       | -         |
| tasks                     | work          | checklist_item             | editable      | -                      | update, delete         | -                                        | -                      | -           | -        | -       | -         |
| undo                      | work          | undo                       | append-only   | -                      | create                 | -                                        | -                      | -           | -        | -       | -         |
| warranty                  | work          | warranty_claim             | state-machine | create                 | -                      | createdAt, amount                        | status                 | -           | -        | -       | -         |

<!-- entity-matrix:end -->

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
- Clients, hooks, controllers. 33 blocks have a `client.ts`; typed controller files exist for two. Record bindings are on every block that has a record page (employees: K1; invoices, quotes and deals: K3a; bookings, expenses, leave and risks: K3b; risks only with the relations block, leave's employee subject only with `owner: "employee"`). EX-1237 (fixed with those two limits, ADR 0822), EX-1238 (fixed, PR #908: the trio is the client, the generic controller and the hooks; three deliberate exceptions in `client-trio.test.ts`).

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
| Permission keys and role defaults | yes (`gen.permissionCatalog`, #903)     | generated catalog migration                              |
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
| Roles and per-record access      | partial | permissions block, record teams (ADR 0134), grants                | keys declared per entity and generated (#903)            | EX-1231, EX-1232, EX-1322 |
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
| Realtime                         | partial | realtime-tables, controllers                                      | fixed (PR #904): `blockRealtimeRefetch`                  | EX-1319                   |
| API keys and OAuth apps          | covered | api-keys, oauth-server, pages                                     | scopes generated in `permission-scopes.ts` (#903)        | EX-1330                   |
| Impersonation                    | partial | impersonation block                                               | actor not recorded on writes                             | EX-1321                   |
| Feature flags                    | partial | flags block                                                       | no entity flag declaration                               | EX-1328                   |
| Concurrency (optimistic locking) | missing | fewer than ten blocks                                             | the rest                                                 | EX-1213                   |
| Bulk operations at scale         | partial | 30 blocks, bulk-actions                                           | shapes differ, limit not declared                        | EX-1209                   |
| Long-running jobs                | partial | queue in about 20 blocks                                          | no common progress shape                                 | EX-1324                   |
| Archival and partitioning        | partial | audit, outbox, notifications                                      | entity tables                                            | EX-1325                   |
| Empty, loading, error states     | partial | record list kit                                                   | fixed (PR #904): `blockListStatus`                       | EX-1326                   |
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

## Follow-up from the example pages (PR 887)

Building the remaining block screens added three rows to the capability matrix
and confirmed two of the generator gaps above. The details and ids are in
[`example-findings.md`](example-findings.md#library-and-block-changes-needed).

- Blocks with no member-callable surface: `field-encryption` (EX-1605),
  `vercel-marketplace` (EX-1606) and `impersonation` (EX-1607, no TypeScript
  client). Each is covered through the screen that shows its effect or through
  raw `api` calls, and each needs a block change before it has a screen of its
  own.
- `reminders` lists by subject only (EX-1609), and `billing` needs Stripe keys
  before the example can install it (EX-1608).
- Permission keys still come from hand-written catalog migrations (EX-807,
  EX-1232, EX-1603), and `gen` rewrites every `*_subject_readable` function when
  a block with subjects is added (EX-1604).

## Progress

Each lane edits only its own subsection, in its first commit (`in progress`), once its PR is open and when it merges. Subsections stay separated by blank lines so parallel branches do not conflict. The program runs parallel PRs as a one-off exception to `.agents/rules/git-workflow.mdc`, which is unchanged; each PR body says "audit program, lane X".

### Lane 0

- Scope: Tracking: Progress and Lane ownership sections, lane checklist
- Status: merged
- Branch: `docs/audit-lane-0`
- PR: [#894](https://github.com/ScaleDockHQ/better-supabase/pull/894)
- Findings: none (docs only)
- Log: 2026-11-12, lane 0 started from main after PR 887 merged; PR #894 opened. 2026-11-12, merged as [#894](https://github.com/ScaleDockHQ/better-supabase/pull/894).

### Lane A

- Scope: Entity surface in the manifest and core list types
- Status: merged
- Branch: `feat/audit-a`
- PR: [#897](https://github.com/ScaleDockHQ/better-supabase/pull/897)
- Findings: EX-1208, EX-1216, EX-1352
- Log: 2026-11-12, lane A started from main in `../bsb-audit-a`; PR #897 opened with `entities` on every manifest, the list contract types and the generated entity matrix. 2026-11-12, merged as [#897](https://github.com/ScaleDockHQ/better-supabase/pull/897).

### Lane B

- Scope: Event verbs, hint prefix rule, one key per block
- Status: merged
- Branch: `feat/audit-b`
- PR: [#900](https://github.com/ScaleDockHQ/better-supabase/pull/900)
- Findings: EX-1230, EX-1233, EX-1234
- Log: 2026-11-12, planned.
- Log: 2026-11-12, lane B started in `../bsb-audit-b` from main. 2026-11-13, merged as [#900](https://github.com/ScaleDockHQ/better-supabase/pull/900).

### Lane C

- Scope: Field-aware invalid_input, generated messages, locale
- Status: merged
- Branch: `feat/audit-c`
- PR: [#898](https://github.com/ScaleDockHQ/better-supabase/pull/898)
- Findings: EX-1235, EX-1236, EX-1317
- Log: 2026-11-12, planned.
- Log: 2026-11-12, lane C started from main in `../bsb-audit-c`.
- Log: 2026-11-12, PR #898 opened (ADR 0709). 2026-11-13, merged as [#898](https://github.com/ScaleDockHQ/better-supabase/pull/898).

### Lane D

- Scope: Shared recurrence, digest and money cores
- Status: merged
- Branch: `feat/audit-d`
- PR: [#899](https://github.com/ScaleDockHQ/better-supabase/pull/899)
- Findings: EX-1290, EX-1291, EX-1293, EX-1315, EX-1316
- Log: 2026-11-12, planned. 2026-11-12, lane D started from main in `../bsb-audit-d`. 2026-11-12, PR #899 opened (ADR 0719 replaces 0197). 2026-11-13, merged as [#899](https://github.com/ScaleDockHQ/better-supabase/pull/899).

### Lane E

- Scope: Example follow-up block fixes
- Status: merged
- Branch: `feat/audit-e`
- PR: [#902](https://github.com/ScaleDockHQ/better-supabase/pull/902), [#914](https://github.com/ScaleDockHQ/better-supabase/pull/914)
- Findings: EX-1602, EX-1604, EX-1605, EX-1606, EX-1607, EX-1610, EX-1612, EX-1613, EX-1614
- Log: 2026-11-12, E1 PR opened (fixes 1604 in part, 1605 in part, 1606, 1607, 1610, 1612, 1614). EX-1602 and EX-1613 remain for E2. 2026-11-13, E1 merged as [#902](https://github.com/ScaleDockHQ/better-supabase/pull/902). 2026-11-13, the E2 work (EX-1602 extractor warning, EX-1613 column renames, EX-1604 and EX-1605 remainder, plus EX-1115 and EX-1614) merged inside the library findings pass, [#914](https://github.com/ScaleDockHQ/better-supabase/pull/914), so all nine rows are closed.

### Lane F

- Scope: pgTAP per block check and MCP mapping
- Status: merged
- Branch: `feat/audit-f`
- PR: [#896](https://github.com/ScaleDockHQ/better-supabase/pull/896)
- Findings: EX-1269, EX-1351, EX-1354
- Log: 2026-11-12, planned.
  2026-11-12, lane F started from main (3220ac7c6a).
  2026-11-12, PR #896 opened: pgTAP rule (87 blocks allowlisted), MCP mapping doc and test; EX-100 to EX-108 and EX-700 to EX-706 are on main.
  2026-11-12, merged as [#896](https://github.com/ScaleDockHQ/better-supabase/pull/896).

### Lane G1

- Scope: Shared page, facets and count implementation
- Status: merged
- Branch: `feat/audit-g1`
- PR: [#906](https://github.com/ScaleDockHQ/better-supabase/pull/906)
- Findings: none closed alone (G1 is the shared base; G2 to G5 close the list rows per category)
- Log: 2026-11-12, planned.
  2026-11-13, lane G1 started from main (6f9b3af232) in `../bsb-audit-g1`.
  2026-11-13, PR #906 opened: shared page, facets and count (ADR 0749), nine blocks moved over, `sso` kept on SCIM paging, `get` added for three entities, migration 20261215140000.
  2026-11-13, merged as [#906](https://github.com/ScaleDockHQ/better-supabase/pull/906).

### Lane G2

- Scope: List contract rollout: work and collaboration
- Status: PR open
- Branch: `feat/audit-g2`
- PR: [#921](https://github.com/ScaleDockHQ/better-supabase/pull/921)
- Findings: EX-1200 to EX-1205, EX-1215, EX-200, EX-204, EX-901
- Log: 2026-11-12, planned.
  2026-11-13, lane G2 started from main (7f4bcbfdf7) in `../bsb-audit-g2`.
  2026-11-13, PR #921: `inspections`, `meetings` and `warranty` take the contract (ADR 0759), `warranty` gains `get`, migration 20261216060002. The other work and collaboration blocks page by their own `before`, `after` or `cursor` shapes (or not at all), so each needs a cursor change; they follow in later G2 PRs and the findings stay partly fixed until then.

### Lane G3

- Scope: List contract rollout: commerce
- Status: PR open #929
- Branch: `feat/audit-g3`
- PR: [#929](https://github.com/ScaleDockHQ/better-supabase/pull/929)
- Findings: EX-1200 to EX-1205, EX-1215, EX-800 to EX-802, EX-811, EX-812, EX-1100 to EX-1105
- Log: 2026-11-12, planned. 2026-11-14, page, facets and count for 11 entities in seven blocks
  (commissions, donations, leases, manufacturing, periods, referrals, shipments), ADR 0769.
  Left for a later lane: the ledger, expenses, funding, accounting, banking, billable-time,
  catalog, inventory, invoices, reviews and tax lists, and `get` for the new entities.

### Lane G4

- Scope: List contract rollout: crm, people and scheduling
- Status: in progress (#918 merged; the lists listed in the log stay for a later G4 PR)
- Branch: `feat/audit-g4`
- PR: [#918](https://github.com/ScaleDockHQ/better-supabase/pull/918) (merged)
- Findings: EX-1200 to EX-1205, EX-1215, EX-600, EX-1000, EX-1001
- Log: 2026-11-12, planned.
  2026-11-13, lane G4 started from main (7f4bcbfdf7) in `../bsb-audit-g4`.
  2026-11-13, PR #918 opened: five entities moved over (ADR 0779): sequences, payroll runs, passes, enrollments and prescriptions; sibling `page_*` functions for the positional lists, `get_enrollment` added. Blocks with extra columns and the permission-heavy lists (contacts, contracts, hiring, time-entries, bookings, leave, calendar, shifts, mail-sync, qualifications, medications) stay for a later lane.

### Lane G5

- Scope: List contract rollout: all other categories
- Status: PR open #920
- Branch: `feat/audit-g5`
- PR: [#920](https://github.com/ScaleDockHQ/better-supabase/pull/920)
- Findings: EX-1200 to EX-1205, EX-1215, EX-300, EX-400, EX-401
- Log: 2026-11-12, planned.
  2026-11-13, lane G5 started from main (7f4bcbfdf7) in `../bsb-audit-g5`.
  2026-11-13, PR #920 opened: `legal_entity`, `course` and `content_entry` page, facet and count (migration 20261216050005). `sso` keeps SCIM paging and its bounded lists. The other lists wait for a per-call tenant, a caller scope or a parent scope (ADR 0789).

### Lane G6

- Scope: Per-call tenant for the shared list surface, and the lists it unlocks
- Status: PR open
- Branch: `feat/audit-g6`
- PR: none yet
- Findings: EX-1200 to EX-1205, EX-1215
- Log: 2026-11-14, lane G6 started from main (125e0e82d8) in `../bsb-audit-g6`.
  2026-11-14, ADR 0939: `entityList` takes `organizationId` per call (`tenantOrOption`, `RequiredTenantOption`). `hostname` (`domains`), `form` (`forms`), `import` runs (`imports`) and `access_request` (`access-requests`) page, facet and count (migration 20261217060006). Deferred with reasons in ADR 0939: `teams` (PowerSync local list), `api-keys` (caller scope in the same function), the caller-scoped, child and no-identity lists of ADR 0789.

### Lane H

- Scope: Generated permission keys, role defaults and scopes
- Status: merged
- Branch: `feat/audit-h`
- PR: [#903](https://github.com/ScaleDockHQ/better-supabase/pull/903)
- Findings: EX-1231, EX-1232, EX-1322, EX-1330, EX-1603, EX-807
- Log: 2026-11-13, lane H started from main in `../bsb-audit-h`.
  2026-11-13, PR #903 opened with validated `entities.<key>.permissions`, `gen.permissionCatalog` and the scope lists (ADR 0799).
  2026-11-13, merged as [#903](https://github.com/ScaleDockHQ/better-supabase/pull/903).

### Lane J

- Scope: expectedVersion, idempotencyKey and optimistic controllers
- Status: merged
- Branch: `feat/audit-j`
- PR: [#905](https://github.com/ScaleDockHQ/better-supabase/pull/905)
- Findings: EX-1212, EX-1213, EX-1214
- Log: 2026-11-13, lane J started from main (6f9b3af232) in `../bsb-audit-j`.
- Log: 2026-11-13, PR #905 opened, then merged as [#905](https://github.com/ScaleDockHQ/better-supabase/pull/905).

### Lane K

- Scope: Client, controller and hooks trio, record bindings
- Status: merged
- Branch: `feat/audit-k`, `feat/audit-k2`, `feat/audit-k4-trio`, `feat/audit-k3`, `feat/audit-k3b`
- PR: [#901](https://github.com/ScaleDockHQ/better-supabase/pull/901), [#904](https://github.com/ScaleDockHQ/better-supabase/pull/904), [#908](https://github.com/ScaleDockHQ/better-supabase/pull/908), [#910](https://github.com/ScaleDockHQ/better-supabase/pull/910), [#912](https://github.com/ScaleDockHQ/better-supabase/pull/912)
- Findings: EX-1237, EX-1238, EX-1319, EX-1326
- Log: 2026-11-12, planned.
  2026-11-13, lane K started from main (6f9b3af232) in `../bsb-audit-k`; K1 is the employees binding.
  2026-11-13, K1 built (ADR 0819): `employeeContractsBinding`. The other seven bindings, the trio, the status union and realtime hooks stay open.
  2026-11-13, K2 (`feat/audit-k2`, ADR 0820, PR #904): EX-1326 and EX-1319 fixed.
  2026-11-13, trio PR #908 (`feat/audit-k4-trio`, ADR 0821): EX-1238 fixed. The SQL-backed bindings (K3) wait for a local stack: 24 of the 32 macOS shared memory segments are held by other worktrees' stacks, so `pnpm supabase:start` refuses.
  2026-11-13, K3a (`feat/audit-k3`, ADR 0822): bindings for invoices, quotes and deals; PR #910.
  2026-11-13, K3b (`feat/audit-k3b`, ADR 0822, PR #912): bindings for bookings, expenses, leave and risks, rebased on main after K3a (#910) merged.
  2026-11-13, all parts merged: K1 #901, K2 #904, trio #908, K3a #910 and K3b #912. EX-1237, EX-1238, EX-1319 and EX-1326 are fixed.

### Lane N

- Scope: Subject labels, party core, manifest links and concerns
- Status: merged
- Branch: `feat/audit-n`
- PR: [#907](https://github.com/ScaleDockHQ/better-supabase/pull/907)
- Findings: EX-1266, EX-1292, EX-1295, EX-1296
- Log: 2026-11-12, planned.
- Log: 2026-11-13, lane N started from main in `../bsb-audit-n`; PR #907 opened with `subjects.label`, the party core, manifest `links` and `concerns` and search defaults. 2026-11-13, merged as [#907](https://github.com/ScaleDockHQ/better-supabase/pull/907).

### Lane I

- Scope: Archive, restore and purge everywhere
- Status: planned
- Branch: `feat/audit-i`
- PR: none yet
- Findings: EX-1206, EX-1207, EX-1230 (verb adoption)
- Log: 2026-11-12, planned.

### Lane L

- Scope: Bulk, export, import target and job shape
- Status: planned
- Branch: `feat/audit-l`
- PR: none yet
- Findings: EX-1209, EX-1210, EX-1211, EX-1324, EX-515 (check #917's set checks first)
- Log: 2026-11-12, planned.

### Lane M1

- Scope: defineEntityPage, list query, route, index
- Status: in progress
- Branch: `feat/audit-m1`
- PR: [#945](https://github.com/ScaleDockHQ/better-supabase/pull/945)
- Findings: EX-1260, EX-1261, EX-1265, EX-1270, EX-001 to EX-003, EX-012, EX-014, EX-410, EX-607
- Log: 2026-11-12, planned. 2026-11-14, PR opened: descriptor, generator outputs, indexes, BS636, filter tree adapter (ADRs 0859, 0860).

### Lane M2

- Scope: Generated columns, detail frame and forms
- Status: planned
- Branch: `feat/audit-m2`
- PR: none yet
- Findings: EX-1262, EX-1263, EX-033, EX-034
- Log: 2026-11-12, planned.

### Lane M3

- Scope: Generated seed, nav, route manifest, coverage, message keys
- Status: planned
- Branch: `feat/audit-m3`
- PR: none yet
- Findings: EX-1264, EX-1267, EX-1268
- Log: 2026-11-12, planned.

### Lane M4

- Scope: Example on generated output, app list helpers removed
- Status: planned
- Branch: `feat/audit-m4`
- PR: none yet
- Findings: EX-1294, EX-1327, EX-813, EX-024 (once the instant allow list is empty)
- Log: 2026-11-12, planned.

### Lane O1

- Scope: Personal data, retention, history tabs, partition
- Status: in progress
- Branch: `feat/audit-o1`
- PR: [#943](https://github.com/ScaleDockHQ/better-supabase/pull/943)
- Findings: EX-1310, EX-1311, EX-1323, EX-1325
- Log: 2026-11-12, planned.
- Log: 2026-11-14, lane O1 started from main (aa43c1d009) in `../bsb-audit-o1`. One PR: `subjectColumn`, `erase`, `legalHold`, `history` and `partition` on the entity surface, `subjectAccessPlan`, `subjectAccessRequest` and `historyTabs`, declarations on `consent`, `data_subject_request` and `field_history`, ADRs 0899 to 0902. No SQL change, so no migration and no pgTAP test; the SQL erase executor per entity stays open (EX-1310).

### Lane O2

- Scope: Plan limits, quota, method meters
- Status: planned
- Branch: `feat/audit-o2`
- PR: none yet
- Findings: EX-1312, EX-1313, EX-1314
- Log: 2026-11-12, planned.

### Lane O3

- Scope: Offline, public events, impersonation actor, flags, invitations
- Status: planned
- Branch: `feat/audit-o3`
- PR: none yet
- Findings: EX-1318, EX-1320, EX-1321, EX-1328, EX-1329, EX-510
- Log: 2026-11-12, planned.

### Lane P

- Scope: Generated skill references, final matrix, close the report
- Status: planned
- Branch: `feat/audit-p`
- PR: none yet
- Findings: EX-1350
- Log: 2026-11-12, planned.

The lanes X0 to X9 below are the findings program. It closes the unfinished rows of [`example-findings.md`](example-findings.md) that no audit lane owns. One lane is one PR on `feat/findings-x<n>` in `../bsb-findings-x<n>`, and its PR body says "findings program, lane Xn". `pnpm check:example-findings` fails when an unfinished row is named by no lane's Findings line and when a lane is `merged` while one of its rows is unfinished, except a row stated `deferred (needs: ...)`, which waits on a maintainer step.

### Lane X0

- Scope: Reconcile the report and this tracker with the merged lanes, repair the report tables, add the X lanes and `check:example-findings`
- Status: in progress
- Branch: `feat/findings-x0`
- PR: none yet
- Findings: EX-1237, EX-1238, EX-1319, EX-1326, EX-611 (closed here; the other lagging rows keep their lane)
- Log: 2026-11-14, lane X0 started from main (b124ee8206) in `../bsb-findings-x0`.

### Lane X1

- Scope: Dev loop and local stack: open bugs and tooling rows (repo tooling, no changeset)
- Status: in progress (#923 merged; EX-313, EX-903, EX-1020 and EX-310 stay deferred)
- Branch: `feat/findings-x1`
- PR: [#923](https://github.com/ScaleDockHQ/better-supabase/pull/923) (merged)
- Findings: EX-309, EX-704, EX-313, EX-318, EX-819, EX-903, EX-430, EX-315, EX-108, EX-050, EX-051, EX-056, EX-1021, EX-505, EX-511, EX-512, EX-605, EX-606, EX-820, EX-207, EX-208, EX-214, EX-316, EX-107, EX-106, EX-902, EX-1507, EX-310, EX-1020
- Log: 2026-11-14, planned; waits for [#917](https://github.com/ScaleDockHQ/better-supabase/pull/917) (merged 2026-11-13, so it can start). 2026-11-14, lane X1 started from main (f6e7d2b78d) in `../bsb-findings-x1`. Fixed in code: `dev:example` script, `dotenv -o`, `tsc --incremental false`, `worktree-setup` (signing keys, app env, workflow world, prune), `env:local` (`WORKFLOW_TARGET_WORLD`, `SUPABASE_JWKS`), `perf-results/`. Documented in tooling.md. EX-313, EX-903, EX-1020 and EX-310 stay deferred, so the lane is not `merged`.

### Lane X2

- Scope: Library follow-ups: what lane H left open, the facet count and the diff rewrites
- Status: merged
- Branch: `feat/findings-x2`
- PR: [#930](https://github.com/ScaleDockHQ/better-supabase/pull/930) (merged)
- Findings: EX-611, EX-506, EX-513, EX-808, EX-1108, EX-016, EX-924, EX-814
- Log: 2026-11-14, lane X2 started from main (f6e7d2b78d) in `../bsb-findings-x2`. EX-016, EX-506, EX-513 and EX-1108 fixed, EX-808, EX-924 and EX-814 measured and closed; ADR 0949 and migrations 20270102100000 to 20270102100004.

### Lane X2b

- Scope: Search and calendar (after audit lane G4 for the calendar; ADRs from the range of X2)
- Status: merged
- Branch: `feat/findings-x2b`
- PR: [#939](https://github.com/ScaleDockHQ/better-supabase/pull/939)
- Findings: EX-1504, EX-1508
- Log: 2026-11-14, planned.
- Log: 2026-11-14, started in `../bsb-findings-x2b`.
- Log: 2026-11-14, EX-1504 measured (the per-type limit moves nothing; scoring only full-text matches takes `search_global` from 0.9 to 1.0 s down to 0.51 s) and EX-1508 fixed (`calendar.bootstrap`). ADR 0950, migration `20270112130000`.

### Lane X3

- Scope: Example-only fixes, and the forms and names on lane C and N
- Status: merged
- Branch: `feat/findings-x3`
- PR: [#926](https://github.com/ScaleDockHQ/better-supabase/pull/926)
- Findings: EX-1505, EX-925, EX-042, EX-804, EX-411, EX-703, EX-104, EX-803, EX-809, EX-610, EX-810, EX-101, EX-402
- Log: 2026-11-14, planned.
- Log: 2026-11-14, started in `../bsb-findings-x3`.
- Log: 2026-11-14, all 13 rows worked: 11 fixed or closed or measured away, EX-104 waits for `AI_GATEWAY_API_KEY`. ADR 0959, migration `20270103120000`.

### Lane X4

- Scope: Admin and billing (a maintainer sets Stripe test keys in the three Vercel environments)
- Status: merged
- Branch: `feat/findings-x4`
- PR: [#924](https://github.com/ScaleDockHQ/better-supabase/pull/924) (merged), follow-up docs fix [#931](https://github.com/ScaleDockHQ/better-supabase/pull/931) (merged)
- Findings: EX-1608, EX-502, EX-507, EX-516
- Log: 2026-11-14, planned.
- Log: 2026-11-14, started in `bsb-findings-x4`.
- Log: 2026-11-14, EX-502, EX-507 and EX-516 fixed; EX-1608 built (webhook and process routes, plan reads on `billing.overview`) and deferred (needs: Stripe test keys and price ids in the three Vercel environments). No migration, so slot 20270104hhmmss stays unused; ADR 0969.
- Log: 2026-11-14, #924 merged; the billing docs page now shows the object form of `checkout`, `portal`, `changePlan`, `cancelAtPeriodEnd`, `invoices`, the tax id calls and `syncSeats`.

### Lane X5

- Scope: Inbox and messaging (after G5; real Slack and WhatsApp adapters need accounts)
- Status: in progress
- Branch: `feat/findings-x5`
- PR: none yet
- Findings: EX-403, EX-404, EX-411, EX-030, EX-422
- Log: 2026-11-14, planned.
- Log: 2026-11-14, in progress.

### Lane X6

- Scope: Workflows (after G2)
- Status: in progress
- Branch: `feat/findings-x6`
- PR: none yet
- Findings: EX-201, EX-202, EX-203, EX-205, EX-210, EX-212, EX-213
- Log: 2026-11-14, planned.
- Log: 2026-11-14, EX-205, EX-210, EX-212 (partly) and EX-213 done (ADRs 0989 and 0990); EX-201 to EX-203 deferred with their needs.
- Log: 2026-11-14, X6b in progress on `feat/findings-x6b` (EX-201 to EX-203 and EX-212; ADRs 0991 to 0994).
- Log: 2026-11-14, X6b done: EX-201 to EX-203 and EX-212 fixed (ADRs 0991 to 0994); one PR, no stack.

### Lane X7

- Scope: AI ops, EX-301 first (a maintainer sets `AI_GATEWAY_API_KEY`)
- Status: in progress
- Branch: `feat/findings-x7`
- PR: [#927](https://github.com/ScaleDockHQ/better-supabase/pull/927)
- Findings: EX-301, EX-302, EX-305, EX-306, EX-307, EX-317
- Log: 2026-11-14, planned.
- Log: 2026-11-14, in progress.

### Lane X8

- Scope: Commerce and finance (after G3)
- Status: in review
- Branch: `feat/findings-x8`
- PR: [#938](https://github.com/ScaleDockHQ/better-supabase/pull/938)
- Findings: EX-805, EX-818, EX-1106, EX-1110 to EX-1113, EX-701
- Log: 2026-11-14, planned.
- Log: 2026-11-14, started in `../bsb-findings-x8`.
- Log: 2026-11-14, EX-805, EX-701, EX-1106 and EX-1110 to EX-1113 fixed (two read functions, migration `20270111120000`, ADR 1009); EX-818 deferred (needs: anonymous sign-ins with a captcha in every Supabase project).

### Lane X9

- Scope: CRM and records (after G4)
- Status: in review
- Branch: `feat/findings-x9`
- PR: #936
- Findings: EX-601, EX-602, EX-032, EX-035, EX-103
- Log: 2026-11-14, planned.
- Log: 2026-11-14, started on `feat/findings-x9`.
- Log: 2026-11-14, opened #936: record sections by subject, quotes and sequences as overview and detail, companies route, `?new=1` create dialogs, deal calendar, timeline, owner assignment and buyer thread (ADRs 1019 to 1021).

## Lane ownership

ADR numbers and migration slots are reserved per lane so parallel branches never collide. A lane that needs more than its ten ADRs asks in its PR; it never takes another lane's range.

- ADR ranges: ten numbers per lane, starting at 0689 (the highest existing ADR is 0688). Lane 0 writes no ADR.
- Migration slots: a lane names its migrations `202612DDhhmmss_<name>.sql` with `DD` equal to the lane's slot, so two lanes never pick the same timestamp. Existing migrations end on 20261112, so every slot sorts after them.

| Lane | ADR range    | Migration slot | Folders and files it owns                                                                                                                                                              |
| ---- | ------------ | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0    | none         | none           | none (`docs/agents` only)                                                                                                                                                              |
| A    | 0689 to 0698 | 20261201hhmmss | `src/blocks/define-block.ts`, `src/core/block-helpers.ts`, `src/blocks/entity-schema.ts`, `catalog:check`; one `entities` entry in every block manifest (additive, one line per block) |
| B    | 0699 to 0708 | 20261202hhmmss | hint catalogs (`block-hints.ts` and each block's hints), `check:naming`; renames across the 13 non-conforming blocks and the webhooks family                                           |
| C    | 0709 to 0718 | 20261203hhmmss | `src/core` error types, `hint-codes.generated.ts`, the errors docs page, `problem.ts`; the example's `use-error-message.ts`                                                            |
| D    | 0719 to 0728 | 20261204hhmmss | `bookings`, `maintenance`, the recurrence, digest and money cores, the list kit; docs and skills that mention `flows`                                                                  |
| E    | 0729 to 0738 | 20261205hhmmss | `field-encryption`, `vercel-marketplace`, `impersonation`, `SessionProvider`, `api` typing, doctor and `gen` (subject and search drift)                                                |
| F    | 0739 to 0748 | 20261206hhmmss | `check:naming` pgTAP rule, the MCP mapping doc and test, `supabase/tests`                                                                                                              |
| G1   | 0749 to 0758 | 20261207hhmmss | shared page, facets and count helpers in `src/core`; the ten blocks that already page                                                                                                  |
| G2   | 0759 to 0768 | 20261208hhmmss | categories work and collaboration                                                                                                                                                      |
| G3   | 0769 to 0778 | 20261209hhmmss | category commerce                                                                                                                                                                      |
| G4   | 0779 to 0788 | 20261210hhmmss | categories crm, people and scheduling                                                                                                                                                  |
| G5   | 0789 to 0798 | 20261211hhmmss | categories admin, ai, automation, content, database, developer, growth, identity, messaging and tenancy                                                                                |
| H    | 0799 to 0808 | 20261212hhmmss | `permissions-model.ts`, `gen` permission output, API key and OAuth scopes, a new migration (never edit pushed ones)                                                                    |
| J    | 0809 to 0818 | 20261213hhmmss | idempotency block, block controllers, `expectedVersion` and `STALE_WRITE` in `src/core`                                                                                                |
| K    | 0819 to 0828 | 20261214hhmmss | client, controller and hooks files of every block (one file set per block), record bindings for invoices, quotes, deals, risks, employees, leave, expenses and bookings                |
| N    | 0829 to 0838 | 20261215hhmmss | `subjects`, the new `party` core, manifest `links` and `concerns`, search registration defaults                                                                                        |
| I    | 0839 to 0848 | 20261216hhmmss | split by category like G: record entities in every category (starts after B and H merge)                                                                                               |
| L    | 0849 to 0858 | 20261217hhmmss | bulk-actions, export stream, `importTarget`, jobs; blocks that already declare bulk, export or import                                                                                  |
| M1   | 0859 to 0868 | 20261218hhmmss | `defineEntityPage` in the page generator, `scale_list_<entity>.test.sql`, doctor index check                                                                                           |
| M2   | 0869 to 0878 | 20261219hhmmss | page generator output for columns, detail frame and forms                                                                                                                              |
| M3   | 0879 to 0888 | 20261220hhmmss | page generator output for seed, nav, route manifest, coverage and message keys                                                                                                         |
| M4   | 0889 to 0898 | 20261221hhmmss | example app (`apps/examples/*`): delete `block-list.ts`, `block-status-list.ts`, `array-list.ts`, `simple-list.ts`, `admin-list.ts` and the finance registry                           |
| O1   | 0899 to 0908 | 20261222hhmmss | data-lifecycle, consents, field-history and `personalData`, retention and partition declarations                                                                                       |
| O2   | 0909 to 0918 | 20261223hhmmss | entitlements, plan limit, quota and meter declarations                                                                                                                                 |
| O3   | 0919 to 0928 | 20261224hhmmss | offline streams, public events and webhook catalog, impersonation actor, entity flags, invitations                                                                                     |
| P    | 0929 to 0938 | 20261225hhmmss | generated skill references under `packages/better-supabase/skills`, the capability matrix in the audit report                                                                          |

The last reserved ADR is 0938; the next free number for later work is 0939.

The findings program continues the numbering after lane P. Each lane X1 to X9 gets ten ADR numbers and a migration slot `202701DDhhmmss` with `DD` equal to the lane number, which sorts after every audit migration (the newest on `main` is `20261215140010`). Lane X0 writes no ADR and no migration, and X2b uses the range of X2. The next free ADR number for later work is 1029.

| Lane | ADR range    | Migration slot | Folders and files it owns                                                                                       |
| ---- | ------------ | -------------- | --------------------------------------------------------------------------------------------------------------- |
| X0   | none         | none           | `docs/agents` and `scripts/check-example-findings.ts`                                                           |
| X1   | 0939 to 0948 | 20270101hhmmss | `scripts/worktree-setup.ts`, the dev-loop scripts and the local stack tooling                                   |
| X2   | 0949 to 0958 | 20270102hhmmss | role defaults, `permissions-model.ts`, session refresh, the facet count option, `supabase:diff` function output |
| X3   | 0959 to 0968 | 20270103hhmmss | example-only pages and forms in `apps/examples/nextjs`                                                          |
| X4   | 0969 to 0978 | 20270104hhmmss | the example's admin and billing routes, the marketplace detail page                                             |
| X5   | 0979 to 0988 | 20270105hhmmss | the inbox and messaging pages (the block folders wait for G5)                                                   |
| X6   | 0989 to 0998 | 20270106hhmmss | the workflow pages (the block folders wait for G2)                                                              |
| X7   | 0999 to 1008 | 20270107hhmmss | the service-role AI blocks' tenant and permission checks, the AI ops pages                                      |
| X8   | 1009 to 1018 | 20270108hhmmss | the commerce and finance pages (the block folders wait for G3)                                                  |
| X9   | 1019 to 1028 | 20270109hhmmss | the CRM and records pages, on the K3 record bindings (the block folders wait for G4)                            |

A lane X does not edit a block folder while that category's audit G or I lane is open; its example-side work can start right away.

### Waves and dependency order

1. Wave 0, serial: lane 0.
2. Wave 1, parallel after lane 0: A, B, C, D, E and F.
3. Wave 2, parallel after A merges: G (G1 first, then G2 to G5), H, J, K and N, plus O1 to O3 planning. G, H, J, K and N touch different files.
4. Wave 3, after the waves above: I needs B and H; L needs G; M1 to M4 need G, H and C (M1 to M4 merge in order); O1 to O3 need A.
5. Wave 4, last: P needs M, I, L and O.

Block folders have one owning lane per wave. Lanes that roll out across all blocks (G, I, K) split by category, and the categories in the table above never overlap.
