# 1102: Load unpdf and mammoth as optional peers for the knowledge extractors

- Status: accepted
- Date: 2026-11-20

## Context

The knowledge block ingests text. Teams also hold PDF and DOCX files, and
chunks should name the page or heading they came from. A PDF or DOCX parser is
large, and the block's bundle baseline counts what the entry loads (ADR 1103).
Architecture invariant 1 and ADR 0036 say every SDK an entry loads is an
optional peer with a tested range, and invariant 12 says lazy loads carry a
comment and a fallback.

## Decision

`pdfExtractor` (a form feed marks a page break for `position.page`) loads `unpdf` and `docxExtractor` loads `mammoth` on first use,
or takes a `load` function so an app passes its own copy. Both are optional
peers (`unpdf >=2.2.1 <3` and `mammoth >=1.13.0 <2`), in the `peers` catalog
and in `tests/optional-peers.test.ts`. Neither package enters the bundle: the
entry holds the lazy import only, through the shared `importOptionalPeer`.

## Alternatives considered

- Regular dependencies. They would install for every app that uses the block
  and move the knowledge entry far past its baseline.
- Shell out to a converter binary. It breaks on runtimes without a shell and
  hides failures behind exit codes.
- Only accept text. That leaves the common case, uploaded documents, to each
  app.

## Consequences

- An app installs `unpdf` or `mammoth` only for the file types it ingests.
- A missing peer throws a `TypeError` that says to install the package or pass
  `load`.
- A new extractor follows the same rule: a peer with a range, loaded lazily.
