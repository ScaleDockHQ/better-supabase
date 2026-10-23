import type { EntitySchema } from "../entity-schema.ts";
import type { RecordBinding, RecordBindingWrite } from "../record-bindings.ts";
import type { Tag, Tags } from "./tags.ts";

import { entitySchema } from "../entity-schema.ts";
import { defineRecordBinding } from "../record-bindings.ts";

/** What tagging or untagging a record takes. */
export interface TagRefInput {
  readonly tagId: string;
}

/** The input schema of the tags binding's `apply` and `remove`. */
export const tagRefInput: EntitySchema<TagRefInput> = entitySchema<TagRefInput>(
  { title: "TagRefInput", fields: { tagId: { kind: "uuid" } } },
);

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

/** The writes of the tags binding. */
export type TagsWrites = {
  /** Puts a tag on the record. */
  readonly apply: RecordBindingWrite<Tags, TagRefInput, boolean>;
  /** Takes a tag off the record. */
  readonly remove: RecordBindingWrite<Tags, TagRefInput, boolean>;
};

/** The tags on a record. */
export const tagsBinding: RecordBinding<
  Tags,
  readonly Tag[],
  never,
  TagsOptimisticAction,
  TagsWrites
> = defineRecordBinding({
  permissions: { read: "read", write: "apply" },
  load: (client: Tags, subject) => client.list({ on: subject }),
  events: ["subject.tagged", "subject.untagged", "tag.*"],
  optimistic: tagsOptimistic,
  writes: {
    apply: {
      input: tagRefInput,
      run: (client: Tags, subject, { tagId }: TagRefInput) =>
        client.attach(subject, tagId),
    },
    remove: {
      input: tagRefInput,
      run: (client: Tags, subject, { tagId }: TagRefInput) =>
        client.detach(subject, tagId),
    },
  },
});
