import type { SavedView, SavedViewPreference } from "./types.ts";

import { rowFields } from "../../core/block-fields.ts";
import { isRecord, optionalText, recordOf, textOf } from "../shared.ts";
import { SAVED_VIEW_KINDS, SAVED_VIEW_SCOPES } from "./types.ts";

function oneOfOr<T extends string>(
  values: readonly T[],
  value: unknown,
  fallback: T,
): T {
  return values.find((item) => item === value) ?? fallback;
}

export function preferenceOf(value: unknown): SavedViewPreference {
  const row = isRecord(value) ? value : {};

  return {
    isDefault: row["isDefault"] === true,
    hidden: row["hidden"] === true,
    pinned: row["pinned"] === true,
  };
}

/**
 * Parses one row of `list_views` into a `SavedView`, the way the block client
 * does. Use it for a page payload RPC that returns the same rows. Throws a
 * `TypeError` on a value that is not an object.
 */
export function viewOf(value: unknown): SavedView {
  const row = recordOf(value, "saved view");
  const state = row["state"];

  return {
    id: textOf(row["id"]),
    list: textOf(row["list"]),
    scope: oneOfOr(SAVED_VIEW_SCOPES, row["scope"], "user"),
    ownerId: optionalText(row["ownerId"]) ?? null,
    teamId: optionalText(row["teamId"]) ?? null,
    name: textOf(row["name"]),
    kind: oneOfOr(SAVED_VIEW_KINDS, row["kind"], "table"),
    state: isRecord(state) ? state : {},
    rank: optionalText(row["rank"]) ?? "V",
    isDefault: row["isDefault"] === true,
    preference: preferenceOf(row["preference"]),
    fields: rowFields(row["fields"]),
  };
}
