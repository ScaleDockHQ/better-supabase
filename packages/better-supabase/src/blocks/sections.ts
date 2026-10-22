import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { DbError } from "../core/errors.ts";
import type { AsyncResult } from "../core/result.ts";
import type { SubjectRef } from "../schema/types.ts";
import type { EntitySchema } from "./entity-schema.ts";

import { entitySchema } from "./entity-schema.ts";

/**
 * The module actions a section needs, such as `{ read: "read", write: "create"
 * }`: the keys of `permissions.<module>` in `blocks.generated.ts`, so a renamed
 * permission key still matches.
 */
export interface SectionPermissions {
  readonly read: string;
  readonly write?: string;
}

/**
 * One write a section takes on its record, such as adding a comment. Generated
 * features turn each one into a Server Action or a mutation.
 */
export interface SectionWrite<Client, Input, Output = unknown> {
  /**
   * The `permissions.<module>` action the write needs, for the `can*` flags.
   * Default: the section's `permissions.write`. The SQL function checks the key
   * again.
   */
  readonly permission?: string;
  /** What the write takes besides the record, as a Standard Schema. */
  readonly input: StandardSchemaV1<unknown, Input>;
  readonly run: (
    client: Client,
    subject: SubjectRef,
    input: Input,
  ) => AsyncResult<Output>;
}

/** Any section write, for constraints. */
export interface AnySectionWrite {
  readonly permission?: string;
  readonly input: StandardSchemaV1;
  readonly run: (
    client: never,
    subject: SubjectRef,
    input: never,
  ) => AsyncResult<unknown>;
}

/** A section's writes, by name. */
export type SectionWrites = Readonly<Record<string, AnySectionWrite>>;

/**
 * One event of a record's history that a section's rows hold, such as a comment
 * or a saved version, for `loadTimeline`.
 */
export interface TimelineItem<Row = unknown> {
  /** Unique within its section. */
  readonly id: string;
  /** What happened, such as `comment` or `version`. */
  readonly kind: string;
  readonly at: Temporal.Instant;
  /** The user who did it, when the row says. */
  readonly actor?: string;
  readonly row: Row;
}

/** What `defineSection` takes. */
export interface SectionDefinition<
  Client,
  Data,
  Options,
  Action,
  W extends SectionWrites = Record<never, never>,
> {
  readonly permissions: SectionPermissions;
  /**
   * The SQL module whose permission keys `permissions` names. Default: the
   * block's first SQL module.
   */
  readonly module?: string;
  /** The section's rows for one subject. */
  readonly load: (
    client: Client,
    subject: SubjectRef,
    options: Options | undefined,
  ) => AsyncResult<Data>;
  /**
   * How many rows each subject has, keyed by `subjectKey` (`type:id`), for a
   * badge on each row of a list.
   */
  readonly count?: (
    client: Client,
    subjects: readonly SubjectRef[],
  ) => AsyncResult<Readonly<Record<string, number>>>;
  /**
   * The section's value for each of many subjects, keyed by `subjectKey`
   * (`type:id`), for a column of a record list (`defineRecordList`). Default:
   * `count`, or else one `load` per subject.
   */
  readonly column?: (
    client: Client,
    subjects: readonly SubjectRef[],
  ) => AsyncResult<Readonly<Record<string, unknown>>>;
  /** The section's rows as timeline entries, for `loadTimeline`. */
  readonly timeline?: (data: Data) => readonly TimelineItem[];
  /** The block events that make the section stale; `*` ends a prefix. */
  readonly events?: readonly string[];
  /** A reducer for `useOptimistic`, applying a pending write to the rows. */
  readonly optimistic?: (state: Data, action: Action) => Data;
  /** The writes the section takes on its record, by name (`add`, `remove`). */
  readonly writes?: W;
}

/**
 * A part of a record page a block owns, such as a comment thread (an extension
 * interface: `apiVersion: 1`). `loadSections` loads it,
 * `createRecordController` keeps it current.
 */
export interface Section<
  Client = never,
  Data = unknown,
  Options = never,
  Action = never,
  W extends SectionWrites = Record<never, never>,
> extends SectionDefinition<Client, Data, Options, Action, W> {
  readonly apiVersion: 1;
  readonly events: readonly string[];
  readonly writes: W;
}

/** Any section, for constraints. */
export interface AnySection {
  readonly apiVersion: 1;
  readonly permissions: SectionPermissions;
  readonly module?: string;
  readonly load: (
    client: never,
    subject: SubjectRef,
    options: never,
  ) => AsyncResult<unknown>;
  readonly count?: (
    client: never,
    subjects: readonly SubjectRef[],
  ) => AsyncResult<Readonly<Record<string, number>>>;
  readonly column?: (
    client: never,
    subjects: readonly SubjectRef[],
  ) => AsyncResult<Readonly<Record<string, unknown>>>;
  readonly timeline?: (data: never) => readonly TimelineItem[];
  readonly events: readonly string[];
  readonly optimistic?: (state: never, action: never) => unknown;
  readonly writes?: SectionWrites;
}

/** A block's sections, by name. */
export type SectionMap = Readonly<Record<string, AnySection>>;

/** The rows a section loads. */
export type SectionData<S> = S extends {
  readonly load: (...args: never) => AsyncResult<infer Data>;
}
  ? Data
  : never;

/** The options a section's `load` takes. */
export type SectionOptions<S> = S extends {
  readonly load: (client: never, subject: never, options: infer O) => unknown;
}
  ? Exclude<O, undefined>
  : never;

/** The names of a section's writes. */
export type SectionWriteName<S> = S extends {
  readonly writes: infer W extends SectionWrites;
}
  ? keyof W & string
  : never;

/** What one of a section's writes resolves to. */
export type SectionWriteOutput<S, N extends string> = S extends {
  readonly writes: infer W extends SectionWrites;
}
  ? N extends keyof W
    ? W[N]["run"] extends (...args: never) => AsyncResult<infer O>
      ? O
      : never
    : never
  : never;

/** What one of a section's writes takes besides the record. */
export type SectionWriteInput<S, N extends string> = S extends {
  readonly writes: infer W extends SectionWrites;
}
  ? N extends keyof W
    ? StandardSchemaV1.InferOutput<W[N]["input"]>
    : never
  : never;

/** A section once loaded: its rows, its error, or hidden from the caller. */
export type SectionResult<Data> =
  | { readonly kind: "ok"; readonly data: Data }
  | { readonly kind: "error"; readonly error: DbError }
  | { readonly kind: "hidden" };

/** Describes a section of a block's record page (`apiVersion: 1`). */
export function defineSection<
  Client,
  Data,
  Options = never,
  Action = never,
  const W extends SectionWrites = Record<never, never>,
>(
  definition: SectionDefinition<Client, Data, Options, Action, W>,
): Section<Client, Data, Options, Action, W> {
  return {
    ...definition,
    apiVersion: 1,
    events: definition.events ?? [],
    // SAFETY: a section without `writes` has none, which is the default `W`.
    writes: definition.writes ?? ({} as W),
  };
}

/** Describes one write of a section, typed by its client and input. */
export function sectionWrite<Client, Input, Output>(
  write: SectionWrite<Client, Input, Output>,
): SectionWrite<Client, Input, Output> {
  return write;
}

/** What a write on one row of a section takes: the row's id. */
export interface SectionRowInput {
  readonly id: string;
}

/** The input schema of a write on one row, such as removing a comment. */
export const sectionRowInput: EntitySchema<SectionRowInput> =
  entitySchema<SectionRowInput>({
    title: "SectionRowInput",
    fields: { id: { kind: "uuid" } },
  });

/** Whether a block event type matches a section's `events` entry. */
export function sectionEventMatches(pattern: string, type: string): boolean {
  return pattern.endsWith("*")
    ? type.startsWith(pattern.slice(0, -1))
    : pattern === type;
}
