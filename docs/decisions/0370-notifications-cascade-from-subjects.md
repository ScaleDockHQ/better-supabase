# 0370: Cascade notifications for every registered subject

## Status

Accepted

## Context

ADR 0325 and the plan's inference list left `blocks.notifications.on` to be written by hand: each subject type needed an entry with `cascade: true` before deleting a subject row cleaned its notifications.

## Decision

When `blocks.notifications.on` is unset, the notifications module reads the subject registry and cascades every registered subject whose table is outside the module's own schema (block tables are created in the same pass, so a trigger could run before its table exists), as if each entry had `cascade: true`. A subject whose events table lacks the `subjectType` or `subjectId` column is skipped instead of failing. An explicit `on` is unchanged and decides for itself.

## Consequences

An app with notifications and subjects gets the `after delete` triggers without config. Apps that list `on` keep their output. A subject table now carries one more trigger for apps that never listed `on`.
