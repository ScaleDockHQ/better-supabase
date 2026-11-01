import type { RecordRef } from "../../schema/types.ts";
import type { EntitySchema } from "../entity-schema.ts";
import type { RecordBinding, RecordBindingWrite } from "../record-bindings.ts";
import type {
  LinkResult,
  Relation,
  Relations,
  UnlinkResult,
} from "./relations.ts";

import { entitySchema } from "../entity-schema.ts";
import { defineRecordBinding } from "../record-bindings.ts";

/** What linking a record to another one takes. */
export interface RelationInput {
  readonly target: RecordRef;
  /** A kind, or its inverse name. */
  readonly kind: string;
  readonly data?: Readonly<Record<string, unknown>>;
}

/** What unlinking a record from another one takes. */
export interface UnlinkRelationInput {
  readonly target: RecordRef;
  readonly kind: string;
}

const TARGET = entitySchema<RecordRef>({
  title: "RecordRef",
  fields: { type: { kind: "string", minLength: 1 }, id: { kind: "string" } },
});

/** The input schema of the relations binding's `link`. */
export const relationInput: EntitySchema<RelationInput> =
  entitySchema<RelationInput>({
    title: "RelationInput",
    fields: {
      target: { kind: "json", schema: TARGET },
      kind: { kind: "string", minLength: 1 },
      data: { kind: "json", optional: true },
    },
  });

/** The input schema of the relations binding's `unlink`. */
export const unlinkRelationInput: EntitySchema<UnlinkRelationInput> =
  entitySchema<UnlinkRelationInput>({
    title: "UnlinkRelationInput",
    fields: {
      target: { kind: "json", schema: TARGET },
      kind: { kind: "string", minLength: 1 },
    },
  });

/** The writes of the relations binding. */
export type RelationsWrites = {
  readonly link: RecordBindingWrite<Relations, RelationInput, LinkResult>;
  readonly unlink: RecordBindingWrite<
    Relations,
    UnlinkRelationInput,
    UnlinkResult
  >;
};

/** A record's links in both directions. */
export const relationsBinding: RecordBinding<
  Relations,
  Relation[],
  never,
  never,
  RelationsWrites
> = defineRecordBinding({
  permissions: { read: "read", write: "manage" },
  module: "relations",
  load: (client: Relations, subject) => client.of({ subject }),
  events: ["subject.linked", "subject.unlinked"],
  writes: {
    link: {
      input: relationInput,
      run: (client: Relations, subject, input: RelationInput) =>
        client.link({
          source: subject,
          target: input.target,
          input: {
            kind: input.kind,
            ...(input.data === undefined ? {} : { data: input.data }),
          },
        }),
    },
    unlink: {
      input: unlinkRelationInput,
      run: (client: Relations, subject, input: UnlinkRelationInput) =>
        client.unlink({
          source: subject,
          target: input.target,
          input: { kind: input.kind },
        }),
    },
  },
});
