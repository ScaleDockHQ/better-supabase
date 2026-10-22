# 0091: Sequences run on enrollments and send through a mailer port

- Status: accepted
- Date: 2026-10-22

## Context

An outreach sequence needs, per recipient, which step they are on, when the
next one runs, which steps are done and why the run ended. The `enrollments`
block (ADR 0077) keeps exactly that shape for any subject in a program of
ordered steps, and ADR 0077 names sequences as a follow-up on its tables.
Sending is the other half: the `mail-sync` block (ADR 0078) sends from a
member's connected Gmail or Microsoft 365 mailbox, threads replies and
records opens, clicks and inbound mail. Sending needs provider tokens and an
HTTP call, which can't happen inside Postgres, and a block may not build
another block's client (ADR 0029).

## Decision

A `sequences` block owns the definition (`sequences`, with its steps as a
JSON array of `email`, `wait` and `task` steps) and a per-recipient row
(`sequence_enrollments`) for what the enrollments block has no place for: the
mailbox, the thread, the next run time, send attempts and the variables. A
recipient's run is an enrollment of the record in the program
`sequence:<id>`, whose steps are the sequence's step ids; changing the steps
resyncs every live run, and the enrollments block refuses to complete or
reset a step of a `sequence:` program, as it does for `course:` programs
(ADR 0085).

`run_due_sequences` runs as the service role. It finishes due wait steps,
creates a `work-items` task for a task step when that block is installed,
and claims due email steps for a lease, returning them to TypeScript. The
client sends each claim through a new `mailer` port (`Pick<MailSync,
"send">`), which `mail-sync` provides and `sequences` consumes as optional,
then reports `sequence_step_sent` or `sequence_step_failed`. A failed send
retries with a linear backoff and exits as `failed` after `maxAttempts`. A
trigger on inbound `mail_messages` ends the runs of the sender, on their
thread or from their address, with the reason `replied`.

## Alternatives considered

- Our own enrollment tables: duplicates ADR 0077's counts, events and
  admin view for no gain.
- Sending from Postgres with `pg_net`: the provider tokens would have to be
  readable in SQL and the result arrives asynchronously, so retries and
  threading get harder.
- A `jobs` handler per email: adds a hard dependency on `jobs` and loses the
  single claim, send, report loop that a cron route can drive.

## Consequences

- Sequence runs show in the enrollments admin page and fire `enrollment.*`
  next to `sequence_enrollment.*`.
- Without `mail-sync`, wait and task steps still run and `runDue` fails with
  `SEQUENCE_NO_MAILER` once an email step is due.
- Sending happens where `runDue` runs, so a sequence sends only as often as
  the app's cron route calls it.
- A/B variants per step and send windows (business hours, time zones) are
  follow-ups.
