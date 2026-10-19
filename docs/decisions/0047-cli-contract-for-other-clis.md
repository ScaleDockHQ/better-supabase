# 0047: Publish the CLI contract other CLIs follow

- Status: accepted; extends 0045
- Date: 2026-10-19

## Context

0045 gave the CLI one command tree, one JSON envelope and agent mode.
Other CLIs that coding agents run in the same repositories, such as an
authorization library's generator, now follow the same contract so an
agent reads every result the same way. Until now the contract lived only in
this CLI's code and docs, so another CLI could drift without either side
noticing.

## Decision

The contract is what this CLI publishes, and another CLI conforms to it:

- **Exit codes.** `0` success, `1` failure, `2` a wrong command line, `3`
  action required (missing input, a login or consent), `130` SIGINT or a
  cancelled prompt, `143` SIGTERM. `65` stays this CLI's own, for
  `gen --metadata`.
- **The envelope.** `--json` prints one `cli-result-v1` document
  (`schemas/cli-result-v1.json`) with `status`, `data`, `error` and `next`.
  `error` is an RFC 9457 problem whose `code` is one of the schema's enum
  values, with the title and exit code `errors.mdx` gives it.
- **The help document.** `--help --json` prints `cli-commands-v1`: `name`,
  `version`, `options` and the command tree, each command with its path,
  description, docs, examples, effects, arguments and options.
- **Consent.** A destructive run in agent mode returns `consent_required`
  with a 16-character hex token, and runs once the same command line comes
  back with `--confirm <token>`. The token is opaque: only the CLI that
  issued it checks it. Each CLI derives it with SHA-256 from at least the
  consent reason and the command line without `--confirm`, and may bind
  more, such as the working directory.
- **Reserved extension codes.** Another CLI may add a code only under a
  name this schema does not use, and lists it in the "Codes from other
  CLIs" section of `errors.mdx` so it is never reused here with another
  meaning. Today these are `dirty_worktree` (exit `3`) and `write_failed`
  (exit `1`).

A change to a shared code, an exit code or the envelope is a breaking
change to the published schema and needs a changeset. A conforming CLI
checks itself against the schema from a pinned release of this package, so
a new code here reaches it when it moves the pin.

## Alternatives considered

- Keep the contract implicit. Each CLI copies the other's code and the
  copies drift, which is what the audit before this change found.
- Publish the contract as its own package. It adds a release train for a
  JSON schema and a table, which the schema file in this package already
  carries.

## Consequences

The schema enum and the `errors.mdx` table are public API for other CLIs
as well as for agents. The Create page's setup commands are checked
against a checked-in copy of the other CLI's `cli-commands-v1`, so a
renamed flag there fails a test here instead of a copied command.
