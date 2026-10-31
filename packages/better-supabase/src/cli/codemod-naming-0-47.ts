import type { Codemod, CodemodResult, ReviewHint } from "./codemod.ts";

import {
  ENTITY_RENAMES_CODEMOD,
  HINT_RENAMES,
  SUBJECT_TYPE_RENAMES,
  TABLE_RENAMES,
} from "../index.ts";
import {
  EVENT_REVIEW,
  EVENT_STRINGS,
  renameSqlEventTypes,
} from "./codemod-events-0-47.ts";
import { withEntityKeysRenamed } from "./sql/config-entity-keys.ts";

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * `ACTIVITY_FORBIDDEN` is the timeline's old code and the activities block's
 * new one, so a literal of it is listed, not rewritten.
 */
const AMBIGUOUS_HINT = "ACTIVITY_FORBIDDEN";

const HINT_STRINGS: Readonly<Record<string, string>> = Object.fromEntries(
  Object.entries(HINT_RENAMES).filter(([old]) => old !== AMBIGUOUS_HINT),
);

const TABLE_PAIRS = Object.values(TABLE_RENAMES).flatMap((module) =>
  Object.values(module),
);

const OLD_TABLES = TABLE_PAIRS.map((table) => table.from);

const TABLE_MOVES = TABLE_PAIRS.map(
  (table) => `\`${table.from}\` is \`${table.to}\``,
);

const quoted = (values: Iterable<string>): RegExp =>
  new RegExp(`["'\`](?:${[...values].map(escapeRegExp).join("|")})["'\`]`);

const REVIEW_0_47: readonly ReviewHint[] = [
  {
    pattern: quoted([AMBIGUOUS_HINT]),
    message:
      "`ACTIVITY_FORBIDDEN` was the timeline's code and is now the activities block's: a timeline check matches `TIMELINE_ENTRY_FORBIDDEN`, an activities check `ACTIVITY_FORBIDDEN`",
  },
  {
    pattern: quoted(Object.keys(SUBJECT_TYPE_RENAMES)),
    message: `Subject types follow the entity's singular: ${Object.entries(
      SUBJECT_TYPE_RENAMES,
    )
      .map(([old, next]) => `\`${old}\` is \`${next}\``)
      .join(
        ", ",
      )}. Old types still resolve until 0.48; rename the ones that name a block's subject`,
  },
  {
    pattern:
      /\baccounting_tax_codes\b|\b(?:save|list)_accounting_tax_codes?\b|\.saveTaxCode\(|\baccounting\.taxCodes\(/,
    message:
      "Tax codes moved to the tax block: read `tax_codes` and `tax_rates` instead of `accounting_tax_codes`, and call `tax.saveCode` and `tax.codes` instead of the accounting `saveTaxCode` and `taxCodes` (`save_tax_code` and `list_tax_codes` in SQL)",
  },
  {
    pattern: /\bpayment_terms_days\b|\bpaymentTermsDays\b/,
    message:
      "Contacts keep payment terms in `payment_terms` rows: replace `payment_terms_days` and `paymentTermsDays` with `customer_terms_id` and `supplier_terms_id` (`customerTermsId` and `supplierTermsId`), and create the terms with `contacts.savePaymentTerm` (the migration guide has the SQL to convert existing days)",
  },
  {
    pattern: /\bactionItems\b|\baction_items\b/,
    message:
      "Postmortem `actionItems` and the `action_items` column are removed: write action items with `addPostmortemAction` (tasks block) and read the postmortem's `actions`",
  },
  {
    pattern: /\bai_document_versions\b/,
    message:
      "AI document versions moved to the versions table (`subject_type = 'ai_document'`, the text in `content`): read them through `documents.versions(documentId)`",
  },
  {
    pattern:
      /acknowledge_compliance_policy|compliance_policy_acknowledgements|policy_acknowledgements|pending_only\s*=>|["'`](?:POLICY_NOT_PUBLISHED|COMPLIANCE_POLICY_NOT_PUBLISHED|compliance\.acknowledge|(?:compliance_)?policy\.acknowledged)["'`]/,
    message:
      "Policy acknowledgements moved onto the acknowledgements block: call `acknowledge('compliance_policy', id)` and `list_my_acknowledgements` instead of `acknowledge_compliance_policy` and `list_compliance_policies(pending_only)`, read `acknowledgements` instead of `policy_acknowledgements`, match `ACKNOWLEDGEMENT_NO_VERSION` and `ACKNOWLEDGEMENT_NOT_ASSIGNED` instead of `POLICY_NOT_PUBLISHED`, grant `acknowledgements.acknowledge` instead of `compliance.acknowledge`, and listen for `acknowledgement.created` instead of `policy.acknowledged`",
  },
  {
    pattern:
      /\b(?:linkInboxContact|unlinkInboxContact|personForInboxContact|contact_identities|person_inbox_contacts|upsert_contact)\b|\bcontacts\.upsert\(|\bbetter_supabase"?\."?contacts\b/,
    message:
      "Inbox contacts are people of the contacts block: a conversation's `contact_id` is a person id, `contact_identities` is `person_identities` (`address` instead of `external_id`), and `person_inbox_contacts` is gone. Use `contacts.findByIdentity`, `addIdentity` and `savePerson` instead of `personForInboxContact`, `linkInboxContact` and the deprecated `inbox.contacts.upsert`, and read `people` instead of the inbox `contacts` table",
  },
  {
    pattern:
      /\bimport_runs\b|\bstart_import\s*\(|\bdefineImport\b|\bappTableImport\b|\bimports\.start\(/,
    message:
      "Import runs name their `source` instead of their `kind`: rename `kind` in `defineImport`, `appTableImport` and queries on `import_runs`, and read `counts` per entity (`{ inserted, updated, unchanged, conflicted, missing }`) and `errors` as `{ entity, key, code, message }`. New code starts runs with `imports.runs.start` and writes through `imports.upsertBatch`",
  },
  {
    pattern:
      /\b(?:saveDefinition|listDefinitions)\s*\(\s*["'`]|\bsave_field_definition\s*\(|\binstall_field_pack\b/,
    message:
      "A field definition's entity is a registered subject type: `save_field_definition` fails with `FIELD_ENTITY_UNKNOWN` for a name that isn't a key of `config.subjects` or a type an installed block registers. Register the type, or map the stored value to one with `blocks.custom-fields.options.entityMap` before `upgrade`, which renames the definitions and their value rows",
  },
  {
    pattern: /\bcreate_attachment\s*\(/,
    message:
      "`create_attachment` takes `document_type`, `source`, `external_id` and `source_path` after `pages`, and the old overloads are dropped: call it by named arguments, or pass the new ones. A `source` must be in `options.sources` or belong to an import run, and a table you adopted for `tables.attachments` maps the five new columns or sets them to `null`",
  },
  {
    pattern: /\bsequences\b[^\n]*\btables\s*:\s*\{[^{}\n]*\bmembers\s*:/,
    message:
      "A `members` table adopted for sequence runs is not moved by the upgrade, which copies only `sequence_enrollments`: copy its rows onto `enrollments` (program `sequence:<id>`) and `enrollment_steps`, then remove the `tables.members` key. The pattern matches a config written on one line; doctor reports the key in any layout as BS425",
  },
  {
    pattern: /\bwork_item_id\b|\bengagement_id\b/,
    message:
      "The task and activity foreign key columns follow the entity: `work_item_id` is `task_id` in `task_checklist_items` and `task_assignees`, and `engagement_id` is `activity_id` in `engagement_subjects`, the recordings and notes tables and `mail_threads`. The upgrade migration renames them in the block tables; rename them in your own queries, views and policies. Tables you adopted keep their columns",
  },
  {
    pattern: new RegExp(
      `\\bbetter_supabase"?\\."?(?:${OLD_TABLES.map(escapeRegExp).join("|")})\\b`,
    ),
    message: `Module tables follow the naming convention, and the upgrade migration renames them: ${TABLE_MOVES.join(
      ", ",
    )}. Queries on an old name fail; tables you adopted keep their names`,
  },
];

const SQL_HINT = new RegExp(
  `'(${Object.keys(HINT_STRINGS).map(escapeRegExp).join("|")})'`,
  "g",
);

/**
 * Renames the hint codes the app's own SQL matches (`hint =
 * 'WORK_ITEM_LOCKED'`).
 */
function renameSqlHints(source: string): CodemodResult {
  const text = source.replaceAll(
    SQL_HINT,
    (_match, hint: string) => `'${HINT_STRINGS[hint] ?? hint}'`,
  );

  const review = source
    .split("\n")
    .flatMap((line, index) =>
      REVIEW_0_47.filter((hint) => hint.pattern.test(line)).map((hint) => ({
        line: index + 1,
        message: hint.message,
      })),
    );

  return { text, review };
}

/** Renames the hint codes, then the event types, in the app's own SQL. */
function renameSql(source: string): CodemodResult {
  const hints = renameSqlHints(source);
  const events = renameSqlEventTypes(hints.text);

  return { text: events.text, review: [...hints.review, ...events.review] };
}

/**
 * `codemod 0.47`: entity keys equal the entity's singular, hint codes follow
 * the entity's new name, and event types are `<entity>.<past verb>` (ADR
 * 0130).
 */
export const CODEMOD_0_47: Codemod = {
  name: ENTITY_RENAMES_CODEMOD,
  description:
    "Renames the keys of blocks.<name>.entities to the entity's singular (work_item to task, engagement to activity, rule to automation, ...), renames hint codes after the entity's new name (WORK_ITEM_NOT_FOUND to TASK_NOT_FOUND, ENGAGEMENT_NOT_FOUND to ACTIVITY_NOT_FOUND, ...) in code and the app's SQL, renames workItemChecklistBinding to taskChecklistBinding, renames event types to <entity>.<past verb> (work_item.created to task.created, rule.removed to automation.deleted, ...) in config, code and the app's SQL, and lists ACTIVITY_FORBIDDEN, the renamed subject types, the split event types such as agent.saved, the support.*, workflow.*, leave.* and waitlist.* patterns and the drive.* and organization.* patterns, postmortem actionItems, ai_document_versions, the old policy acknowledgement calls, the sequence run events and queries on renamed module tables for review",
  subpathImports: {
    "blocks/tasks": { workItemChecklistBinding: "taskChecklistBinding" },
  },
  strings: { ...HINT_STRINGS, ...EVENT_STRINGS },
  configFile: (source) =>
    withEntityKeysRenamed({ ok: true, text: source, review: [] }),
  sqlFile: renameSql,
  review: [...REVIEW_0_47, ...EVENT_REVIEW],
};
