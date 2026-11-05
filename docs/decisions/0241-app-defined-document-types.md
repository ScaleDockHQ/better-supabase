# 0241: Let apps define document types with a variable contract

- Status: accepted
- Date: 2026-11-05

## Context

Document templates knew seven fixed types. A notice or a certificate needs a
template, a frozen snapshot and a typed contract like an invoice does, but the
type list sat in check constraints, the contract function and the variable
dispatcher.

## Decision

`options.documentTypes` adds types by name. Each entry gives a variable list
and the schema-qualified app function `(tenant, document_id)` that returns the
payload as jsonb. The check constraints, `document_template_contract`, the
type errors and `document_variables` include them, so templates, snapshots,
`render_document` and `freeze_document` work unchanged. Built-in names are
refused. This is additive to ADR 0145: the built-in contract and
`DOCUMENT_CONTRACT_VERSION` do not change.

The TypeScript client takes `DocumentTypeName`, a built-in name or any string,
and `validateDocumentTemplate` takes the app contracts as an optional third
argument.

## Consequences

The app owns the builder function and keeps it in step with the declared
contract. The database cannot check the payload against the contract.
