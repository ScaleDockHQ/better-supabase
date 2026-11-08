# 0269: Close the fields and work gaps of the base layer

- Status: accepted
- Date: 2026-11-07

## Context

Part 5 of the declarative base layer plan lists the work and HR items an app
wrote beside the blocks. An audit found most of them in place: tasks already
take `fields` on create, leave and expenses have an employee owner, employee
statuses map to the app's enum (`typed`, `ctx.cast`, `ctx.appValues`, covered
by `employees-shapes.test.ts`), hiring has `stages` and `hiringManager`, and
approvals take extra columns on requests and policies, with floors that tenant
policies only tighten.

## Decision

- Tasks: `locked` joins the optional columns, so a table without a lock maps
  it to null. The guard trigger leaves out `TASK_LOCKED` and the tree read
  returns `locked: null`. The plan says "the optional columns" without naming
  them; the other columns (`team`, `priority`, `due_at`, `rank`) are read by
  dozens of statements, so they stay required.
- Time entries: `options.on` lists the record types an entry can be tracked
  on. The plan's rule is that `on` means a record-type binding. A type outside
  the list fails with `TIME_SUBJECT_INVALID`; an entry without a record is
  never restricted, and no option means any readable record type, as before.

## Not done

- Hiring simplification: the plan names no concrete change beyond the stages
  and the hiring manager, which exist. Nothing is added.
- Extra columns on approval items, steps and decisions: requests and policies
  carry them, and no app asked for more.

## Consequences

A table without a lock column no longer needs one for the tasks block. An app
that restricted time subjects in its own trigger can delete it and list the
types in `options.on`.
