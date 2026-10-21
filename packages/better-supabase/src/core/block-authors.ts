import { optionalText } from "./block-helpers.ts";
import { isRecord } from "./guards.ts";

/**
 * Who wrote a comment or uploaded a file, from `profiles` (with the `profiles`
 * module): its display name and avatar URL.
 */
export interface Author {
  readonly id: string;
  readonly name: string | undefined;
  readonly avatarUrl: string | undefined;
}

/** A row's `author` object as an `Author`, or `undefined`. */
export function authorOf(value: unknown): Author | undefined {
  if (!isRecord(value) || typeof value["id"] !== "string") {
    return undefined;
  }

  return {
    id: value["id"],
    name: optionalText(value["name"]),
    avatarUrl: optionalText(value["avatarUrl"] ?? value["avatar_url"]),
  };
}
