import type { CodemodResult, ReviewHint } from "./codemod.ts";

import {
  currentEventTypes,
  EVENT_TYPE_RENAMES,
  EVENT_TYPE_SPLITS,
  isOldEventType,
  renamed,
} from "../index.ts";

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * Old event patterns that 0.46 listed as permission wildcards instead of
 * rewriting them, so a string with one may still mean a permission.
 */
const AMBIGUOUS = new Set(["support.*", "workflow.*"]);

/**
 * Old event patterns that are also current permission wildcards: as an event
 * pattern `waitlist.*` is now `waitlist_entry.*`, as a permission it stays.
 */
const PERMISSION_WILDCARDS = new Set(["leave.*", "waitlist.*"]);

/** The event types the codemod rewrites in strings, old to new. */
export const EVENT_STRINGS: Readonly<Record<string, string>> =
  Object.fromEntries(
    Object.entries(EVENT_TYPE_RENAMES).filter(
      ([old]) => !AMBIGUOUS.has(old) && !PERMISSION_WILDCARDS.has(old),
    ),
  );

/** Split event types that no block emits any more, such as `agent.saved`. */
const OLD_SPLITS = Object.keys(EVENT_TYPE_SPLITS).filter(
  (type) => isOldEventType(type) && !PERMISSION_WILDCARDS.has(type),
);

const typeList = (type: string): string =>
  currentEventTypes(type)
    .map((each) => `\`${each}\``)
    .join(" or ");

const quoted = (keys: Iterable<string>): RegExp =>
  new RegExp(`["'\`](?:${[...keys].map(escapeRegExp).join("|")})["'\`]`);

/** The event types and patterns the codemod lists for review. */
export const EVENT_REVIEW: readonly ReviewHint[] = [
  {
    pattern: quoted(AMBIGUOUS),
    message:
      "An event pattern and a permission wildcard from before 0.46 look the same here: as an event pattern, `support.*` is now `support_session.*` and `workflow.*` is `workflow_definition.*`; as a permission, `support.*` is `impersonation.*` and `workflow.*` is `workflows.*` plus `workflow_editor.*`",
  },
  {
    pattern: quoted(PERMISSION_WILDCARDS),
    message:
      "An event pattern and a permission wildcard look the same here: as a permission it stays; as an event pattern, `leave.*` is now `leave_request.*` plus `leave_balance.*` and `waitlist.*` is `waitlist_entry.*`",
  },
  ...OLD_SPLITS.map((type): ReviewHint => ({
    pattern: quoted([type]),
    message: `The event \`${type}\` is now ${typeList(type)}: subscribe to the one this code needs, or to both`,
  })),
  {
    pattern: quoted(["drive.*", "organization.*"]),
    message:
      "As an event pattern, `drive.*` no longer matches the node events (now `drive_node.*`) and `organization.*` no longer matches the SSO domain events (now `sso_domain.*`): add the new pattern where this code needs them",
  },
];

const SQL_TYPE = new RegExp(
  `'(${Object.keys(EVENT_STRINGS).map(escapeRegExp).join("|")})'`,
  "g",
);

/** Renames the event types in the app's own SQL (`type = 'work_item.created'`). */
export function renameSqlEventTypes(source: string): CodemodResult {
  const text = source.replaceAll(
    SQL_TYPE,
    (_match, type: string) => `'${renamed(EVENT_STRINGS, type)}'`,
  );

  const review = source
    .split("\n")
    .flatMap((line, index) =>
      EVENT_REVIEW.filter((hint) => hint.pattern.test(line)).map((hint) => ({
        line: index + 1,
        message: hint.message,
      })),
    );

  return { text, review };
}
