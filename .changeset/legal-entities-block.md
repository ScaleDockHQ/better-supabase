---
"better-supabase": minor
---

New `legal-entities` block (`better-supabase/blocks/legal-entities`): several companies inside one organization, with one default and a settings fallback. A single-company organization needs no configuration.

- `create`, `update`, `setDefault`, `archive`, `restore`, `get` and `list` keep each legal entity's code, name, address, VAT number, chamber of commerce number, IBAN, BIC, logo, default currency and fiscal calendar (`fiscalYearStartMonth`, `taxPeriod`). The first entity becomes the default, a partial unique index allows one default per organization, and the default can't be archived.
- `of(id?)` calls `legal_entity_of(tenant, id)`: a null id resolves to the default entity, and an entity of another organization fails.
- `resolveSetting(key, legalEntityId?)` calls `resolve_setting(tenant, key, legal_entity)` and falls back from the legal entity to the organization to the code default. `settings`, `setSetting` and `resetSetting` keep the per-entity values in `legal_entity_settings`. The settings block's client gains `resolve`, which needs the legal-entities block.
- `blocks.legal-entities.options.on` adds a nullable `legal_entity_id` to the tables of `invoices`, `quotes`, `orders`, `numbering`, `accounting`, `inventory_locations` and `settings`. Null means the default entity. Contacts stay shared.
- The permission keys are `legal_entities.read` and `legal_entities.manage`; members get `read`. Events are `legal_entity.created` and `legal_entity.updated`.

Add `"legal-entities": {}` to `blocks`, run `better-supabase add legal-entities` and generate a migration. List the modules to extend in `options.on`.
