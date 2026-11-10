# 0643: Run large audit exports as a queue job, and read the unread count from the browser

- Status: accepted
- Date: 2026-11-10
- Amends: 0614

## Context

The example's audit export streams up to 100,000 rows and refuses a larger range, so an
organization with millions of entries had to cut its range by hand. The unread badge in the static
shell loaded its numbers through a Server Action, which put a server round trip behind every
broadcast on `notifications:<user id>`.

## Decision

**Audit export job.** `GET /api/audit/export` still streams up to 100,000 rows, and `?probe=1`
answers the capped row count so the page can choose. `POST /api/audit/export-jobs` (its own route, so the
streaming route does not load the queue client, which added 68 KB raw to it) queues the `audit_export` job on
Vercel Queues (the jobs block's `vercelQueueProvider`). The job writes the CSV with
`audit.exportToStorage` as the service role to `audit/<organization id>/<job id>.csv` in the private
`data-exports` bucket, then sends the requester an `audit.export.ready` notification whose
`actionPath` is `GET /api/audit/export/<job id>`. That route signs a 15 minute link for the caller's
own organization path only. Without `JOBS_BACKEND=vercel` the POST answers with the missing setting,
because the example runs no worker for the SQL backend.

**Browser counts.** The badge and the summary call the `notification_counts` function on the
`api` schema through the browser client, the call `notifications.counts()` makes on the server. The
notifications client itself stays out of the browser: importing it added about 18 KB raw to every
app route. The `loadNotificationCounts` Server Action is removed. ADR 0614's lite client has no PostgREST, so
these routes keep the full browser client, which the badge already loaded.

## Alternatives considered

- Raising the streaming limit: a request would hold a connection and a function for minutes.
- A new export bucket: needs a migration and policies for a file the data exports bucket already
  holds privately.

## Consequences

An export of any size completes in the background and the download link is one notification away.
The unread count no longer costs a server invocation per broadcast.

The audit export job adds three routes and code to the routes that import the audit block. The First
Load JS baseline (raw up to about 800 bytes, 109 entries) and the server baseline (five entries,
raw up to 280 bytes) are re-measured from a fresh build of this branch after merging main, and the
three new routes are added by `update`. The guard in `next-build.test.ts` is unchanged.
