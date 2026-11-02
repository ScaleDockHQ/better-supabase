import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { DbError } from "../core/errors.ts";
import type { AsyncResult } from "../core/result.ts";
import type { RecordRef } from "../schema/types.ts";
import type { EntitySchema } from "./entity-schema.ts";

import { entitySchema } from "./entity-schema.ts";

/**
 * The module actions a binding needs, such as `{ read: "read", write: "create"
 * }`: the keys of `permissions.<module>` in `blocks.generated.ts`, so a renamed
 * permission key still matches.
 */
export interface RecordBindingPermissions {
  readonly read: string;
  readonly write?: string;
}

/**
 * One write a binding takes on its record, such as adding a comment. Generated
 * record types turn each one into a Server Action or a mutation.
 */
export interface RecordBindingWrite<Client, Input, Output = unknown> {
  /**
   * The `permissions.<module>` action the write needs, for the `can*` flags.
   * Default: the binding's `permissions.write`. The SQL function checks the key
   * again.
   */
  readonly permission?: string;
  /** What the write takes besides the record, as a Standard Schema. */
  readonly input: StandardSchemaV1<unknown, Input>;
  readonly run: (
    client: Client,
    subject: RecordRef,
    input: Input,
  ) => AsyncResult<Output>;
}

/** Any binding write, for constraints. */
export interface AnyRecordBindingWrite {
  readonly permission?: string;
  readonly input: StandardSchemaV1;
  readonly run: (
    client: never,
    subject: RecordRef,
    input: never,
  ) => AsyncResult<unknown>;
}

/** A binding's writes, by name. */
export type RecordBindingWrites = Readonly<
  Record<string, AnyRecordBindingWrite>
>;

/**
 * One event of a record's history that a binding's rows hold, such as a comment
 * or a saved version, for `loadTimeline`.
 */
export interface TimelineItem<Row = unknown> {
  /** Unique within its binding. */
  readonly id: string;
  /** What happened, such as `comment` or `version`. */
  readonly kind: string;
  readonly at: Temporal.Instant;
  /** The user who did it, when the row says. */
  readonly actor?: string;
  readonly row: Row;
}

/** What `defineRecordBinding` takes. */
export interface RecordBindingDefinition<
  Client,
  Data,
  Options,
  Action,
  W extends RecordBindingWrites = Record<never, never>,
> {
  readonly permissions: RecordBindingPermissions;
  /**
   * The SQL module whose permission keys `permissions` names. Default: the
   * block's first SQL module.
   */
  readonly module?: string;
  /** The binding's rows for one subject. */
  readonly load: (
    client: Client,
    subject: RecordRef,
    options: Options | undefined,
  ) => AsyncResult<Data>;
  /**
   * How many rows each subject has, keyed by `subjectKey` (`type:id`), for a
   * badge on each row of a list.
   */
  readonly count?: (
    client: Client,
    subjects: readonly RecordRef[],
  ) => AsyncResult<Readonly<Record<string, number>>>;
  /**
   * The binding's value for each of many subjects, keyed by `subjectKey`
   * (`type:id`), for a column of a record list (`defineRecordList`). Default:
   * `count`, or else one `load` per subject.
   */
  readonly column?: (
    client: Client,
    subjects: readonly RecordRef[],
  ) => AsyncResult<Readonly<Record<string, unknown>>>;
  /** The binding's rows as timeline entries, for `loadTimeline`. */
  readonly timeline?: (data: Data) => readonly TimelineItem[];
  /**
   * Copies the binding's rows from one record to another and returns how many
   * it copied, for `bsb.recordAt(type, id).copyTo`. Leave it out for rows that
   * must not be copied, such as versions or signatures.
   */
  readonly copy?: (
    client: Client,
    from: RecordRef,
    to: RecordRef,
  ) => AsyncResult<number>;
  /** The block events that make the binding stale; `*` ends a prefix. */
  readonly events?: readonly string[];
  /** A reducer for `useOptimistic`, applying a pending write to the rows. */
  readonly optimistic?: (state: Data, action: Action) => Data;
  /** The writes the binding takes on its record, by name (`add`, `remove`). */
  readonly writes?: W;
}

/**
 * A part of a record page a block owns, such as a comment thread (an extension
 * interface: `apiVersion: 1`). `loadBindings` loads it,
 * `createRecordController` keeps it current.
 */
export interface RecordBinding<
  Client = never,
  Data = unknown,
  Options = never,
  Action = never,
  W extends RecordBindingWrites = Record<never, never>,
> extends RecordBindingDefinition<Client, Data, Options, Action, W> {
  readonly apiVersion: 1;
  readonly events: readonly string[];
  readonly writes: W;
}

/** Any binding, for constraints. */
export interface AnyRecordBinding {
  readonly apiVersion: 1;
  readonly permissions: RecordBindingPermissions;
  readonly module?: string;
  readonly load: (
    client: never,
    subject: RecordRef,
    options: never,
  ) => AsyncResult<unknown>;
  readonly count?: (
    client: never,
    subjects: readonly RecordRef[],
  ) => AsyncResult<Readonly<Record<string, number>>>;
  readonly column?: (
    client: never,
    subjects: readonly RecordRef[],
  ) => AsyncResult<Readonly<Record<string, unknown>>>;
  readonly timeline?: (data: never) => readonly TimelineItem[];
  readonly copy?: (
    client: never,
    from: RecordRef,
    to: RecordRef,
  ) => AsyncResult<number>;
  readonly events: readonly string[];
  readonly optimistic?: (state: never, action: never) => unknown;
  readonly writes?: RecordBindingWrites;
}

/** The rows a binding loads. */
export type RecordBindingData<S> = S extends {
  readonly load: (...args: never) => AsyncResult<infer Data>;
}
  ? Data
  : never;

/** The options a binding's `load` takes. */
export type RecordBindingOptions<S> = S extends {
  readonly load: (client: never, subject: never, options: infer O) => unknown;
}
  ? Exclude<O, undefined>
  : never;

/** The names of a binding's writes. */
export type RecordBindingWriteName<S> = S extends {
  readonly writes: infer W extends RecordBindingWrites;
}
  ? keyof W & string
  : never;

/** What one of a binding's writes resolves to. */
export type RecordBindingWriteOutput<S, N extends string> = S extends {
  readonly writes: infer W extends RecordBindingWrites;
}
  ? N extends keyof W
    ? W[N]["run"] extends (...args: never) => AsyncResult<infer O>
      ? O
      : never
    : never
  : never;

/** What one of a binding's writes takes besides the record. */
export type RecordBindingWriteInput<S, N extends string> = S extends {
  readonly writes: infer W extends RecordBindingWrites;
}
  ? N extends keyof W
    ? StandardSchemaV1.InferOutput<W[N]["input"]>
    : never
  : never;

/** A binding once loaded: its rows, its error, or hidden from the caller. */
export type RecordBindingResult<Data> =
  | { readonly kind: "ok"; readonly data: Data }
  | { readonly kind: "error"; readonly error: DbError }
  | { readonly kind: "hidden" };

/** Describes a binding of a block's record page (`apiVersion: 1`). */
export function defineRecordBinding<
  Client,
  Data,
  Options = never,
  Action = never,
  const W extends RecordBindingWrites = Record<never, never>,
>(
  definition: RecordBindingDefinition<Client, Data, Options, Action, W>,
): RecordBinding<Client, Data, Options, Action, W> {
  return {
    ...definition,
    apiVersion: 1,
    events: definition.events ?? [],
    // SAFETY: a binding without `writes` has none, which is the default `W`.
    writes: definition.writes ?? ({} as W),
  };
}

/** Describes one write of a binding, typed by its client and input. */
export function recordBindingWrite<Client, Input, Output>(
  write: RecordBindingWrite<Client, Input, Output>,
): RecordBindingWrite<Client, Input, Output> {
  return write;
}

/** What a write on one row of a binding takes: the row's id. */
export interface RecordRowInput {
  readonly id: string;
}

/** The input schema of a write on one row, such as removing a comment. */
export const recordRowInput: EntitySchema<RecordRowInput> =
  entitySchema<RecordRowInput>({
    title: "RecordRowInput",
    fields: { id: { kind: "uuid" } },
  });

/** Whether a block event type matches a binding's `events` entry. */
export function recordEventMatches(pattern: string, type: string): boolean {
  return pattern.endsWith("*")
    ? type.startsWith(pattern.slice(0, -1))
    : pattern === type;
}
