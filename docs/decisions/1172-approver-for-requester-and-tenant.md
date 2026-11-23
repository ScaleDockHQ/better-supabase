# 1172: Give approverFor the requester and the tenant

- Status: accepted
- Date: 2026-11-22
- Amends: 1164

## Context

`functions.approverFor` received only the request kind and id (ADR 1164). A
provider that resolves approvers from the manager chain has to read the request
row to learn who filed it and in which tenant, which repeats a lookup the block
already made.

## Decision

The template also accepts `{requester}` (the requester's user id, a uuid
expression) and `{tenant}`. A template is read when it names any of `{id}`,
`{requester}` or `{tenant}`; one that names none is still ignored. Direct
decisions pass the row's columns. An approval step only has the subject id, so
it reads both through scalar subselects on the block's request table. The
fields stay optional and `apiVersion` stays 1, because an existing template
keeps working unchanged.

## Consequences

Providers can drop their own request lookup. Doctor's decider check (BS706) and
the provider kit follow the same rule.
