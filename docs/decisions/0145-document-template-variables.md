# 0145: Give document templates a typed variable contract

- Status: accepted
- Date: 2026-10-30

## Context

Quotes, invoices, packing slips and dunning letters render from templates, but
the data a template can read is whatever the renderer passes. A template can't
be written against a stable shape, per-entity and per-language variants have no
lookup order, and the texts around a document (payment terms, legal notes,
dunning wording) live in code or in free-text fields.

## Decision

- **A variable contract.** `DocumentTemplateVariables` has the keys `company`,
  `party`, `lines`, `taxSummary`, `paymentTerms`, `openBalance` and `texts`. It
  is published as a JSON Schema under `schemas/`, and
  `document_template_variables(document_type, document_id)` builds it in SQL so
  every renderer gets the same data.
- **A lookup order.** Template keys gain `legal_entity_id` (ADR 0142). The
  lookup order is entity and language, entity, organization and language,
  organization. The language comes from the customer.
- **Tenant-editable text blocks.** `template_text_blocks(key, language,
  legal_entity_id, body)` hold the wording, referenced as
  `{{ texts.<key> }}` and resolved with the same order.
- **Additive contract.** Variables are added in new optional keys. Removing or
  retyping one needs a new contract version, like other extension interfaces
  (architecture rule 10).

## Alternatives considered

- **Let each renderer build its own data.** Templates would break between
  renderers and between document types.
- **Text blocks as settings.** Settings have no language or per-entity lookup
  with this order.
- **A template language per document type.** One contract keeps the editor and
  the docs simple.

## Consequences

- A tenant can edit wording and layout per entity and language without code.
- The schema is a public surface: changes need a changeset and a docs update.
- Revisit if a document type needs data the contract can't carry, which would
  add an optional key.
