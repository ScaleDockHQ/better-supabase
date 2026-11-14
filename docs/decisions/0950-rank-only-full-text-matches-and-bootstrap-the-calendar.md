# 0950: Rank only full-text matches and bootstrap the calendar

- Status: accepted
- Date: 2026-11-14

## Context

Lane X2b closes two example findings that need a library change.

- EX-1504: `search_global` in `supabase/tests/scale/scale_search_global.test.sql`
  took 0.86 to 1.43 s at tier L (200,000 filler documents of 40 subject types
  that share the query's words, so the trigram branch matches every one). The
  finding named a smaller candidate limit per subject type as the lever.
- EX-1508: `/calendar` made 11 calls in one wave, among them `list_calendars`
  twice, `list_calendar_events` twice and one reminders read per upcoming event.

## Decision

- `search` computes `ts_rank_cd` only for rows the full-text index matched. A row
  that only the trigram index matched scored `0 + 0 + similarity` before, and
  scores the same now, without two `ts_rank_cd` calls over its document.
  Results and scores are unchanged. Measured on the same stack, before and after
  (`SCALE_MS`, milliseconds, tier L):

  | Call                       | Before    | After     |
  | -------------------------- | --------- | --------- |
  | `search_global`            | 901 / 996 | 512 / 513 |
  | `search_global_prefix`     | 338 / 411 | 341 / 357 |
  | `search_global_typed`      | 44 / 52   | 36 / 47   |
  | `search_global_unreadable` | 204 / 235 | 203 / 243 |

  A same-session comparison of the old and new function bodies on a busier
  machine gave 1,055 to 1,142 ms before and 659 to 671 ms after.

- The smaller limit per subject type was built and measured in four variants
  (a cap of twice the page per type before the read check, batching the read
  check with `can_subjects`, the cap with the score change, and a gate that skips
  the trigram branch once the full-text branch fills the pool). The cap alone and
  the cap with the score change moved nothing: the time is the scan and scoring
  of the matching rows, and the read check of 100 candidates costs 6 to 7 ms.
  Batching with `can_subjects` made the typed call 60 times slower (2.9 s against
  44 ms), because it checks all 100 candidates where the per-row check stops at
  the page size. The gate saved 150 ms only for the unreadable query and changes
  which hits a long query returns. None of them ships.
- The calendar block gains `calendar_bootstrap(tenant, range_start, range_end,
  upcoming_start, upcoming_end)` and `calendar.bootstrap(...)`. It calls
  `list_calendars` and `list_calendar_events` as the caller and, with the
  reminders block installed, `list_my_reminders` for `calendar_event` subjects
  (a caller without `reminders.manage` gets none). It lives in
  `src/sql/modules/calendar-bootstrap.ts`, so the block's own files change by one
  import, one call and one contract entry. The client expands both event lists
  with `expandOccurrences`.
- The example's `/calendar` reads `loadCalendarPage` once; the month card and the
  reminders card both use that entry, so the page makes one calendar call instead
  of the calendar reads of both cards.
- `20270107130000_x2b_search_calendar.sql` carries both functions.

## Alternatives considered

- A `can_subjects` batch in `search`, as `search_page` does. `search` stops at the
  page size, so batching checks more rows than it needs (see above).
- Raising the trigram similarity threshold. It drops typo matches for every
  caller to speed up a fixture where all documents match.
- A bootstrap that returns expanded occurrences from SQL. Series expand in
  TypeScript (`occurrences.ts`); a second expansion in SQL would have to match it.

## Consequences

A search over a corpus where most documents match by trigram only spends about
half the time. The per-type limit stays open as an idea: revisit it if a real
corpus shows the read check, not the scan, as the cost. The calendar example makes
one database call for its data, and any app can use `calendar.bootstrap` for a
calendar page.
