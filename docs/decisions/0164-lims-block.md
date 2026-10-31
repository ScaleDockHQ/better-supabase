# 0164: Laboratory samples are tested against limits and raise nonconformities

- Status: accepted
- Date: 2026-10-31

## Context

A laboratory receives samples, measures them with methods that have
specification limits, and may release a sample only when the results hold.
`forms` already captures readings, `cases` already runs nonconformities, and
`assets` and `qualifications` already say which instrument may be used when.

## Decision

`lims` is a block (`better-supabase/blocks/lims`) with three tables:
`lims_methods`, `lims_samples` and `lims_results`. All are adoptable
(ADR 0098). A sample is a subject of type `lims_sample`.

- A method has a key, a unit and an optional lower and upper limit. The outcome
  of a result (`in_spec` or `out_of_spec`) is computed when the result is
  recorded and stored, so a later change to the limits does not rewrite history.
- A sample moves from `registered` to `in_testing` on its first result, then to
  `completed`, and ends `released` or `rejected`. It accepts results only while
  it is registered or in testing, so a released record is never altered.
- An out of specification result opens a case of the kind named by
  `options.nonconformityKind` (default `nonconformity`) through `open_case_as`,
  stores the case id on the result and emits `lims_result.flagged`. The case
  source is `lims` when `options.sources` of the cases block lists it and
  `internal` otherwise. Without the cases block the result is still flagged.
- `release_sample` refuses while the latest result of any method (by test time)
  is out of specification.
- `options.instrumentQualification` names a qualification type. A result then
  needs an `instrumentId` that is an asset of the organization holding that
  qualification on the test date, checked with `qualified_holders`. Without the
  option an instrument is optional and unchecked.
- A method can name a form; a result can carry the form submission, which is
  checked against the organization.
- The permission keys are `lims.read`, `lims.write` and `lims.manage`.

## Alternatives considered

- Computing the outcome on read: rejected, since a changed limit would change
  past results.
- Letting a released sample take a retest: rejected, since a release is the
  record that testing ended. A retest is a new sample.
- A dedicated nonconformity table: rejected, since `cases` has the pipeline,
  the actions and the close guard.

## Consequences

A laboratory gets traceable results, a case for every failure and a release
gate with no extra tables beyond the three. A retest of a failed sample needs a
new sample linked through `relations`. Instrument checks cost one call to the
qualifications block per result.
