# 0324: Protect the options the config codemod must not touch

## Status

Accepted

## Context

Config inference removes lines an app wrote only because the schema could not be read. The `config` codemod deletes such lines. A codemod that grows to cover more inferences can delete a choice the schema can't imply, such as a remap, a reserved slug or an audit exemption.

## Decision

`PROTECTED_OPTIONS` in `src/cli/codemod-config.ts` lists the options the codemod never edits: remaps (`names`, `functions`, `permissions`), the organization slug options, invitation accept and preview, `roles`, the audit options (`restricted`, `ipHeader`, `staffClaim`, `subjectColumns`, `exempt`), attachment options, `api`, `ownTablePolicies`, `tenantColumn`, `powersync` and doctor `sources`. A test runs the codemod over a config with each option, in a grouped and a flat shape, and fails when one disappears.

The CentraKit fixture config has a line budget of 800 in `tests/validation-centrakit`, to go under 400 once app files carry its columns. Lienlink's 162-line budget has no committed fixture, so it is checked by hand.

## Consequences

A new inference that removes a protected option fails the test. The real CentraKit config is still about 4,000 lines; the dry run of the `config` codemod finds nothing to remove there.
