# 0163: Digital asset management is renditions and usage rights on drive files

- Status: accepted
- Date: 2026-10-31

## Context

A brand or media team needs more than a file store: a thumbnail and a web size
of each file, and a record of who may use a file, where and until when. The
drive already has a versioned `PreviewRenderer` port for preview pages, and
`collections` and `custom-fields` already group records and describe them.

## Decision

`dam` is a block (`better-supabase/blocks/dam`) with two tables:
`dam_renditions` (one row per file and kind) and `dam_usage_rights`. Both are
adoptable (ADR 0098). Both point at the drive file by id and the block does not
require `drive`, so a file can also come from an app table.

- Renditions are made through the drive's `PreviewRenderer`. Each kind in the
  `renditions` option names a renderer and the page to keep. The client
  uploads the page to the `dam` bucket and records the rendition with
  `record_rendition`. A renderer that throws leaves a `failed` row with the
  message and the other kinds go on. No renderer is bundled.
- A usage right has a licensee, an optional territory and channel (absent
  means all), a start date and an optional expiry date. Its status (`upcoming`,
  `active`, `expired`, `revoked`) is computed from the dates and `revoked_at`,
  never stored, so it can't drift. A revoked right stays in the history.
- `check_usage` allows a use when a right is active that day and names the
  territory and channel, or names none. A file without any right is not
  allowed.
- `notify_expiring_usage_rights(days)` runs as the service role. It notifies
  the member who granted each right that ends within the window and keeps the
  expiry date it reminded for, so a repeat run stays quiet and a new date
  allows a new notice.
- Brand collections add no tables: a collection of drive files and custom
  fields on the same records already cover them.
- The permission keys are `dam.read` and `dam.write`.

## Alternatives considered

- A rendition table per renderer: rejected, since the kind column covers it and
  the port stays the only extension point.
- Storing the right's status: rejected, since a nightly job would have to keep
  it true.
- A dedicated brand collection table: rejected, since `collections` has the
  same shape and sharing.

## Consequences

An app can show a file's thumbnail and warn before a licence ends with no
extra tables. Enforcing a right on download is the app's call to
`checkUsage`. A later change that adds renderer kinds with several pages per
kind needs a new column, not a new port.
