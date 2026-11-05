# 0237: A filings preset on the evidence primitives

## Status

Accepted

## Context

Apps that prepare, sign, send and later defend documents need the same blocks together: versions, signatures, approvals, shipments and an audit trail. ADRs 0234 to 0236 added transactions, evidence tags and chain proofs; no preset combined them.

## Decision

Add the `filings` preset in the `verticals` group. It is `saas` plus contacts, relations, imports, document-templates, numbering, versions, signatures, approvals, attachments, shipments, ledger, cases, reminders and governance. It adds no module of its own and stays domain neutral.

## Consequences

The preset page shows an evidence table with the `append-only`, `function-writes` and `chain` tags. Content hashes on attachments, proof of delivery on shipments, the deadlines block and app-defined document types are not part of this decision and are planned separately.
