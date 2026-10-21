import type { DbError } from "../core/errors.ts";
import type { AsyncResult } from "../core/result.ts";
import type { SubjectRef } from "../schema/types.ts";

/**
 * The module actions a section needs, such as `{ read: "read", write: "create"
 * }`: the keys of `permissions.<module>` in `blocks.generated.ts`, so a renamed
 * permission key still matches.
 */
export interface SectionPermissions {
  readonly read: string;
  readonly write?: string;
}

/** What `defineSection` takes. */
export interface SectionDefinition<Client, Data, Options, Action> {
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
  /** The block events that make the section stale; `*` ends a prefix. */
  readonly events?: readonly string[];
  /** A reducer for `useOptimistic`, applying a pending write to the rows. */
  readonly optimistic?: (state: Data, action: Action) => Data;
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
> extends SectionDefinition<Client, Data, Options, Action> {
  readonly apiVersion: 1;
  readonly events: readonly string[];
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
  readonly events: readonly string[];
  readonly optimistic?: (state: never, action: never) => unknown;
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

/** A section once loaded: its rows, its error, or hidden from the caller. */
export type SectionResult<Data> =
  | { readonly kind: "ok"; readonly data: Data }
  | { readonly kind: "error"; readonly error: DbError }
  | { readonly kind: "hidden" };

/** Describes a section of a block's record page (`apiVersion: 1`). */
export function defineSection<Client, Data, Options = never, Action = never>(
  definition: SectionDefinition<Client, Data, Options, Action>,
): Section<Client, Data, Options, Action> {
  return { ...definition, apiVersion: 1, events: definition.events ?? [] };
}

/** Whether a block event type matches a section's `events` entry. */
export function sectionEventMatches(pattern: string, type: string): boolean {
  return pattern.endsWith("*")
    ? type.startsWith(pattern.slice(0, -1))
    : pattern === type;
}
