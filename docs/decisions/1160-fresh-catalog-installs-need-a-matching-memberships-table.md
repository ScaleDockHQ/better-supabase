# 1160: Fresh catalog installs fail on a memberships table made for the roles model

- Status: accepted
- Date: 2026-11-21

## Context

ADR 1118 kept the permissions escalation check without an integration test, because installing the permissions module with the `catalog` access model failed with `memberships_role_fkey cannot be implemented`. The catalog model stores `memberships.role` as a uuid with a foreign key to `roles.id`. The roles model stores the role key as text.

## Decision

The failure is not a defect in the module. `memberships` is created with `create table if not exists`, so a database that already holds the table keeps the column type it was made with, and the catalog foreign key can't join a text column to a uuid. The integration suites commit module installs into one shared database, so a catalog install that follows a roles-model install meets exactly that table. A fresh database installs both models.

Changing the access model of an installed app is a data migration (a new uuid column filled from `roles.key`, then the swap). No `upgrade` step does it today, and this ADR does not add one. The integration harness (`tests/integration/block-session.ts`) now drops `better_supabase.memberships` when its role column type differs from what the layout's model needs, and `BlockSession.organization` inserts the role by key or by id to match. `tests/integration/permissions-escalation.integration.test.ts` covers the role ceiling (`PERMISSIONS_ROLE_CEILING`) and the key ceiling (`PERMISSIONS_KEY_CEILING`) against the catalog model.

## Alternatives considered

Making `memberships` migrate its own column in the module was rejected: it rewrites a table that holds every member of every organization, and the risk belongs to a reviewed migration. Skipping the test again was rejected.

## Consequences

The escalation check has an integration test. An app that wants the catalog model after installing the roles model needs a migration it writes itself. Revisit this if two models ever need to switch with `upgrade`.
