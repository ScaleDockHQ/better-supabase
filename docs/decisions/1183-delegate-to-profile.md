# 1183: Reserve a delegated task for a named profile

- Status: accepted
- Date: 2026-11-22

## Context

`delegate_task` assigned a user and stored `task_actor(profile)` in `delegate_profile`. That value is the label of whoever delegated, never read by a client, and it reserved nothing, so a task handed to one agent profile of a user could be claimed by any profile.

## Decision

`delegate_task(task, to_user, profile, to_profile)` takes a new `to_profile` text and replaces the three-argument function (the old one is dropped). With `to_profile`, `delegate_profile` stores `{ name, userId }`: the task is reserved for the profile of that user. A claim under another name or by another user raises `TASK_RESERVED` (42501) when the session is an agent; `claim_next_task` skips such tasks. A person with write access can take a reserved task over, which clears the reservation. A claim that matches keeps it. `claim_next_task` accepts `filter.delegateProfile` to pick only tasks reserved for that name. The reservation clears on the next `delegate_task`, when the reserved user is unassigned (an after-delete trigger on the assignees table), and when the task closes (the guard trigger). Reads return `delegateProfile`, the client's `delegate` takes `toProfile`, and `task.delegated` carries `toProfile`.

Module version 7 adds an upgrade step that clears the delegator labels version 6 stored, so no old value reads as a reservation. The step skips tables managed by the app.

## Alternatives considered

A separate reservation table was rejected: one nullable column that reads with the task is enough. Storing only the name was rejected: a reservation for `scout` has to mean the `scout` of the delegated user.

## Consequences

An agent holding a reserved task's profile claims it; other agents never do. Adopters on version 6 lose the delegator label, which nothing read.
