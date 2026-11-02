import type { EntitySchema } from "../entity-schema.ts";
import type { RecordBinding, RecordBindingWrite } from "../record-bindings.ts";
import type { ReactionCount, Reactions } from "./reactions.ts";

import { subjectKey } from "../../core/block-subjects.ts";
import { entitySchema } from "../entity-schema.ts";
import { defineRecordBinding } from "../record-bindings.ts";

/** What toggling a reaction on a record takes. */
export interface ReactionToggleInput {
  readonly emoji: string;
}

/** The input schema of the reactions binding's `toggle`. */
const reactionToggleInput: EntitySchema<ReactionToggleInput> =
  entitySchema<ReactionToggleInput>({
    title: "ReactionToggleInput",
    fields: { emoji: { kind: "string", minLength: 1 } },
  });

/** The writes of the reactions binding. */
export type ReactionsWrites = {
  /** Adds the caller's reaction, or removes it when it is already there. */
  readonly toggle: RecordBindingWrite<
    Reactions,
    ReactionToggleInput,
    readonly ReactionCount[]
  >;
};

/** The reactions on a record, counted by emoji. */
export const reactionsBinding: RecordBinding<
  Reactions,
  readonly ReactionCount[],
  never,
  never,
  ReactionsWrites
> = defineRecordBinding({
  permissions: { read: "read", write: "create" },
  module: "reactions",
  load: (client: Reactions, subject) =>
    client
      .summary([subject])
      .map((summary) => summary[subjectKey(subject)] ?? []),
  events: ["reaction.*"],
  writes: {
    toggle: {
      input: reactionToggleInput,
      run: (client: Reactions, subject, { emoji }: ReactionToggleInput) =>
        client.toggle({ subject, emoji }),
    },
  },
});
