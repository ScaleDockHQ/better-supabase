---
"better-supabase": minor
---

Pages the CRM pipeline blocks by the block list contract (ADR 1077).
`segments`, `forecasts`, `pipelines`, `deals`, `quotes` and `contracts` gain
`page`, `facets`, `count` and `get`, and `contracts` adds `obligationPage`,
`obligationFacets` and `obligationCount`. `contacts` gains `companyPage` and
`personPage` with their facets and counts, plus `companyById` and `personById`.
`mail-sync` gains `threadPage` and `accountPage` with their facets and counts,
plus `getThread` and `getAccount`. Each list takes `q`, sorts, array filters and
a keyset cursor, and a `get` for an unknown id returns a `not_found` error. The
SQL adds `page_segments`, `page_forecast_snapshots`, `page_pipelines`,
`get_pipeline`, `page_deals`, `get_deal`, `page_quotes`, `get_quote`,
`page_contracts`, `page_contract_obligations`, `page_companies`, `page_people`,
`page_mail_threads` and `page_mail_accounts`, and the generated schema files
need `better-supabase upgrade`. The array methods keep working and are
deprecated.

| Old                                | New                         |
| ---------------------------------- | --------------------------- |
| `segments.list`                    | `segments.page`             |
| `segments.get`                     | `segments.getSegment`       |
| `forecasts.list`                   | `forecasts.page`            |
| `pipelines.list`                   | `pipelines.page`            |
| `contracts.list`                   | `contracts.page`            |
| `contracts.obligations`            | `contracts.obligationPage`  |
| `contacts.listCompanies`           | `contacts.companyPage`      |
| `contacts.listPeople`              | `contacts.personPage`       |
| `contacts.getCompany`, `getPerson` | `companyById`, `personById` |
| `mailSync.accounts`                | `mailSync.accountPage`      |
| `mailSync.threads`                 | `mailSync.threadPage`       |
| `mailSync.thread`                  | `mailSync.getThread`        |
