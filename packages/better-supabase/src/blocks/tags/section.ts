import type { Section } from "../sections.ts";
import type { Tag, Tags } from "./tags.ts";

import { defineSection } from "../sections.ts";

/** A pending tag or untag, for `useOptimistic`. */
export type TagsOptimisticAction =
  | { readonly type: "tag"; readonly tag: Tag }
  | { readonly type: "untag"; readonly id: string };

/**
 * A record's tags with a pending write applied: `tag` adds the tag once,
 * `untag` takes it out.
 */
export function tagsOptimistic(
  state: readonly Tag[],
  action: TagsOptimisticAction,
): readonly Tag[] {
  switch (action.type) {
    case "tag": {
      return state.some((tag) => tag.id === action.tag.id)
        ? state
        : [...state, action.tag];
    }

    case "untag": {
      return state.filter((tag) => tag.id !== action.id);
    }

    default: {
      const never: never = action;

      return never;
    }
  }
}

/** The tags on a record. */
export const tagsSection: Section<
  Tags,
  readonly Tag[],
  never,
  TagsOptimisticAction
> = defineSection({
  permissions: { read: "read", write: "apply" },
  load: (client: Tags, subject) => client.forSubject(subject),
  events: ["subject.tagged", "subject.untagged", "tag.*"],
  optimistic: tagsOptimistic,
});
