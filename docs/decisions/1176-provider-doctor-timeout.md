# 1176: Bound the provider's doctor command

- Status: accepted
- Date: 2026-11-22

## Context

`authorization.doctor.command` ran with a fixed 60 second limit. A provider
that needed longer had no way to say so, and a command that timed out after
printing some output was read as if it had finished. `doctor --update-baseline`
gave a new BS705 entry the reason of any BS705 entry, although each provider
finding is a different check under the one code.

## Decision

`authorization.doctor.timeoutMs` sets the limit, 60000 by default. A command
the limit stops is a BS705 finding that names the setting, whatever it printed
before. A finding the provider reports with `severity: "error"` already fails
the run under the default `--fail-on`; a test now covers it.

`updatedBaseline` copies a reason between entries of one group. The group is the
code, except for BS705, where the provider's own code that leads the target
names it.

## Consequences

A slow provider doctor is configurable and its timeout is visible. A BS705
entry in the baseline needs its own reason unless another entry has the same
provider code. The config schema gains one optional field, so `apiVersion` stays 1.
