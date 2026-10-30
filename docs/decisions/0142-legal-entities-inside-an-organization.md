# 0142: Model several legal entities inside one organization

- Status: accepted
- Date: 2026-10-30

## Context

An organization (the tenant) is the isolation boundary for data and
permissions. Real companies run several legal entities with their own VAT
number, bank account, logo, fiscal year, number series and books, while they
share contacts, products, members and permissions. Today a second entity means
a second organization, which splits contacts and users, or free-text fields on
documents, which breaks numbering and reporting per entity.

## Decision

- **A `legal-entities` block.** `legal_entities` holds the code, name, address,
  VAT and chamber numbers, IBAN and BIC, logo, default currency, fiscal
  settings and an `is_default` flag, with one default per organization
  (partial unique index).
- **Opt-in columns.** `blocks.legal-entities.options.on` lists the modules that
  get a nullable `legal_entity_id` (invoices, quotes, orders, numbering,
  accounting, inventory locations, settings), added through each module's
  column hook. Null means the default entity, resolved by
  `legal_entity_of(tenant, id)`. With the block absent nothing changes, so a
  single-entity organization needs no configuration.
- **Settings fall back.** `legal_entity_settings` and
  `resolve_setting(tenant, key, legal_entity)` fall back from the entity to
  the organization to the code default.
- **Contacts stay shared.** The tenant scope (ADR 0099) stays the only
  isolation rule. A legal entity is a dimension inside it, never a second
  tenant, so it adds no new authorization boundary. Permissions are
  `legal_entities.read` and `legal_entities.manage`; events are
  `legal_entity.created` and `legal_entity.updated`.

## Alternatives considered

- **One organization per entity.** Contacts, products and members would need
  copying and syncing.
- **A mandatory `legal_entity_id` everywhere.** It forces a column, a default
  and a migration on organizations that have one entity.
- **A row-level policy per entity.** Entities share people and permissions, so
  a second isolation layer would only add cost.

## Consequences

- Numbering, taxes, templates and books can scope per entity later (PRs 6, 7,
  11 and 18) through one column.
- Reports across entities need an explicit filter; a user sees every entity of
  the organization they belong to.
- Revisit if an entity needs its own members or permissions, which would call
  for a separate organization.
