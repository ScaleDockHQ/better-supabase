# 0606: Inline the subject check in the reaction read policies

- Status: accepted
- Date: 2026-11-10
- Amends: 0424

## Context

The reactions read and insert policies and the scores read policy called
`reaction_subject_visible`, a plpgsql function, once per row (ADR 0424 did the same for
attachments). `scale_reactions_read` (60,000 customers, 12,000 reactions on them, one tenant)
counts the reactions as a member through the function in 4,863 ms.

## Decision

The three policies render the `case subject_type when ... exists (...)` expression over the row's
columns through `inlineSubjectReadable` (qualified with the table, the tenant permission checked
as a set, ADR 0426). A type whose table a later module creates goes to the function. The function
stays for `react` and `vote`. `inlineSubjectReadable` takes `module`, `guest`, `live` and
`typeNotNull`, so other modules can use it.

## Measured

The same count through the policy: 20 ms. The pgTAP suite passes unchanged on a reset stack.

## Not done: activities

The activity link read policy and the activity read check were inlined the same way and failed
the suite with `infinite recursion detected in policy for relation "activities"`: an activity is
itself a subject, so the inlined `exists` on its table reads the links policy again. They keep
`can_subject`. A module whose own tables are subjects needs the function, or a subject list
without them.

## Consequences

`better-supabase upgrade` rewrites `reactions`; the migration replaces three policies. The other
families (deals, consents, sla, observations, care plans, medications, field history, funding,
deadlines, knowledge) are not inlined; each needs the recursion check first.
