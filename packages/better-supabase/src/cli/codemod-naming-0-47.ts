import type { Codemod, CodemodResult, ReviewHint } from "./codemod.ts";

import {
  ENTITY_RENAMES_CODEMOD,
  HINT_RENAMES,
  SUBJECT_TYPE_RENAMES,
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
    pattern: /\bactionItems\b|\baction_items\b/,
    message:
      "Postmortem `actionItems` are deprecated and removed in 0.48: with the tasks block, write them with `addPostmortemAction` and read the postmortem's `actions`",
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
    "Renames the keys of blocks.<name>.entities to the entity's singular (work_item to task, engagement to activity, rule to automation, ...), renames hint codes after the entity's new name (WORK_ITEM_NOT_FOUND to TASK_NOT_FOUND, ENGAGEMENT_NOT_FOUND to ACTIVITY_NOT_FOUND, ...) in code and the app's SQL, renames workItemChecklistBinding to taskChecklistBinding, renames event types to <entity>.<past verb> (work_item.created to task.created, rule.removed to automation.deleted, ...) in config, code and the app's SQL, and lists ACTIVITY_FORBIDDEN, the renamed subject types, the split event types such as agent.saved, the support.*, workflow.*, leave.* and waitlist.* patterns and the drive.* and organization.* patterns, postmortem actionItems and ai_document_versions for review",
  subpathImports: {
    "blocks/tasks": { workItemChecklistBinding: "taskChecklistBinding" },
  },
  strings: { ...HINT_STRINGS, ...EVENT_STRINGS },
  configFile: (source) =>
    withEntityKeysRenamed({ ok: true, text: source, review: [] }),
  sqlFile: renameSql,
  review: [...REVIEW_0_47, ...EVENT_REVIEW],
};
