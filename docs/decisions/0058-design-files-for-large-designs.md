# 0058: Hand designs too large for a URL to init as a design file

- Status: accepted
- Date: 2026-10-20

## Context

A Create design rides on the URL as `&design=` (ADR 0040), capped at
`MAX_DESIGN_CODE_LENGTH` (6000 characters) so the link stays usable. A larger
design had no way to reach `better-supabase init` or `apply` without a saved
project in the cloud app (ADR 0057): Create could only offer the generated
`better-supabase.config.ts`, which the user had to copy into place by hand and
which skipped the checks `init --preset` runs.

The cloud app's API and MCP server also validated design payloads with their
own schema and a cast, because only `designIssues` was public. A design the
canvas refused could pass the server, and the other way round.

## Decision

A design too large for a URL travels as a JSON design file,
`better-supabase.design.json` (`DESIGN_FILE`), holding `preset` (the preset
code) and `design` (the design object, with `version` when it needs format 1).
`designFileSource` writes it and `readDesignFile` reads it, both in
`src/preset/design.ts`. `init --preset` and `apply --preset` read a path ending
in `.json` as a design file, through `src/cli/preset-input.ts`, and then treat
it exactly like a URL with both codes.

`parseDesign` checks the shape of a design object, and `checkDesign` in
`better-supabase/create` checks a design object, code or URL against a preset
with every rule the canvas and `sql sync` apply. It returns issues instead of
throwing, and `code: null` for a valid design too long for a URL.

## Alternatives considered

- Raise the URL cap. Browsers and chat tools truncate long links, and a cap
  only moves the problem.
- Download only the config file. It skips the preset checks, can't be merged
  by `apply`, and loses the design as data.
- Store large designs on a server and pass an id. The library would need a
  network call and a service, which ADR 0040 rules out.
- Let `--preset` read any file. A `.json` suffix keeps preset names and codes
  unambiguous.

## Consequences

Create can offer "Download the design file" when `encodeDesign` throws
`DesignTooLongError`, and the cloud app can validate with `checkDesign`
instead of its own schema. The file format is public: adding a key needs a
reader that accepts it, the same way a new design format does.
