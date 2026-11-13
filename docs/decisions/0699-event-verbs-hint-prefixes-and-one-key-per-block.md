# 0699: Fix the event verbs and hint prefixes, and give each block one key

- Status: accepted
- Date: 2026-11-12
- Amends: 0130, 0246, 0380

## Context

The block consistency audit (`docs/agents/block-consistency-audit.md`, lane B)
found three kinds of naming drift that ADR 0130 states in a sentence and
nothing checks.

- Event verbs. `cancelled` ends 18 records, `voided` three, and `closed`,
  `withdrawn`, `revoked`, `rejected`, `declined`, `denied` and `refused` each
  end others. Two events still used verbs ADR 0130 bans: `message.edited` and
  `drive_node.document_saved`.
- Hint prefixes. Ten hint catalogs used a prefix their block name does not
  give (`EVAL_`, `HOSTNAME_`, `SUPPORT_`, `CARE_`, `BOM_`, `SSF_`,
  `TIMESHEET_`, `FIELD_`, `PRESCRIPTION_`, `WEBHOOK_IN_`), so a code did not say
  which block raised it.
- Block keys. The webhooks family had the manifest names `webhooks` and
  `incoming-webhooks`, the SQL module and config names `webhooks-out` and
  `webhooks-in`, and the hint catalog key `incoming-webhooks`. The
  `webhook-inbox` block already used one key everywhere.

## Decision

1. The event verb vocabulary is the lifecycle verbs of ADR 0130 (`created`,
   `updated`, `deleted`, `archived`, `restored`, `purged`) plus domain verbs.
   The verbs that end a record keep separate meanings, so none of them is
   renamed into another:
   - `cancelled`: stopped before it took effect or finished, by someone with
     authority over it. Spelled with two l.
   - `voided`: an issued document made invalid and kept for the record.
   - `closed`: finished normally; `reopened` reverses it.
   - `withdrawn`: taken back by whoever submitted it.
   - `revoked`: taken back by whoever granted it.
   - `rejected`: refused by a reviewer of a submission.
   - `declined`, `denied` and `refused`: refused by the recipient of an offer
     or invitation, by the owner of a resource and by a controller of a legal
     request.
2. A record that belongs to another one may use the pair `<child>_added` and
   `<child>_removed` on its parent (`organization.member_removed`,
   `collection.entry_removed`). The bare verb `removed` stays banned.
3. `check:naming` fails on the verbs `saved`, `upserted`, `edited`, `canceled`
   and `removed`, and on a verb that ends in `_set`, `_saved` or `_edited`.
   They are the `eventVerbs` keys of `api/naming.json`. `message.edited` is
   `message.updated` and `drive_node.document_saved` is
   `drive_node.document_updated`, each as an `event` row. Deleting a record is
   still `deleted`; lane I adopts `archived` as the verb for records that keep
   their row, so this ADR renames nothing from `deleted`.
4. A hint code starts with a run of the block's name words, the last in
   singular or plural (`AI_EVAL_` for `ai-evals`, `TIME_ENTRIES_` for
   `time-entries`), or with the noun of an entity of the block that the
   `hints.allowlist` of `api/naming.json` lists. Codes of shared cores keep
   their prefix in every block (`hints.shared`: `ACTOR_`, `CREDENTIAL_`,
   `IMPORT_ITEM_`, `NUMBER_` and `ORGANIZATION_ROLE_UNKNOWN`). The check fails
   on a code that matches none of them and on an allowlist entry that no code
   uses any more, so the list only shrinks. Ten prefixes are renamed
   (`EVAL_` to `AI_EVAL_`, `HOSTNAME_` to `DOMAIN_`, `SUPPORT_` to
   `IMPERSONATION_`, `CARE_` to `DECISION_SUPPORT_`, `BOM_` to
   `MANUFACTURING_BOM_`, `SSF_` to `SECURITY_EVENT_`, `TIMESHEET_` to
   `TIME_ENTRIES_TIMESHEET_`, `FIELD_` to `CUSTOM_FIELD_`, `PRESCRIPTION_` to
   `E_PRESCRIBING_` and `WEBHOOK_IN_` to `INCOMING_WEBHOOK_`), each code as a
   `hint` row. `CREDENTIAL_*` comes from the credentials core and
   `IMPORT_ITEM_INVALID` and `ORGANIZATION_ROLE_UNKNOWN` from shared SQL, so
   `mail-sync`, `workflow-editor` and `organizations` keep them.
5. A block has one key. The manifest name is the SQL module name, the config
   key under `blocks`, the hint catalog key and the coverage key. The SQL
   modules `webhooks-out` and `webhooks-in` are `webhooks` and
   `incoming-webhooks`, as `blocks.webhooks` and `blocks.incoming-webhooks`
   `configKey` rows of `api/naming.json`. `FORMER_BLOCK_NAMES` makes the
   generated data file rename the `better_supabase.blocks` row, and
   `20261202090001_better_supabase_module_data_347f6bcf.sql` does the same for
   the fixture. `tests/blocks/registry.test.ts` fails when a module has a name
   other than its block's, except for the six modules a block installs as a
   second part (`invitations`, `seeds`, `chat-sdk-state`, `drive-files`,
   `recurrence`, `housekeeping`).

## Alternatives considered

- Collapse the ending verbs into `cancelled` and `rejected`. It would lose the
  difference between an invoice that was voided and an order that was
  cancelled, and it renames dozens of events for apps that listen to them.
- Allow any hint prefix that is an entity noun. The finding exists because a
  reader cannot tell the block from `SUPPORT_` or `BOM_`.
- Rename the manifests to the module names. The manifest names are the docs
  URLs, the exports and the generated clients; the module names are only the
  config key and the registry row.

## Consequences

An app that matches one of the renamed hint codes, listens for
`message.edited` or `drive_node.document_saved`, or names `webhooks-out` or
`webhooks-in` under `blocks` changes the name. `better-supabase codemod naming`
rewrites the config key and `better-supabase upgrade` renames the registry row.
Outbox rows already written keep their old event type, and error codes already
logged keep their old hint. The hint prefix allowlist has 27 blocks today and
only shrinks.

The longer block names and hint codes add 28 to 55 raw bytes to 31 server routes
of the Next.js example, so their entries in `tests/next-build/server-baseline.json`
rise by that amount. No client first-load number changes.
