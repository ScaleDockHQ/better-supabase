import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { PermissionSet } from "../blocks/access/permissions.ts";
import type { GeneratedBlocks } from "../blocks/block-config.ts";
import type { AnyBlock } from "../blocks/define-block.ts";
import type {
  AnySectionWrite,
  SectionData,
  SectionResult,
  SectionWriteInput,
  SectionWriteName,
  SectionWriteOutput,
} from "../blocks/sections.ts";
import type { SubjectRef } from "../schema/types.ts";
import type { SectionName, SectionNamed } from "./sections.ts";

import { can as holds } from "../blocks/access/permissions.ts";
import { dbError } from "../core/errors.ts";
import { AsyncResult } from "../core/result.ts";
import { findSection } from "./sections.ts";

/** The section blocks of a feature, keyed like `blockSet.blocks`. */
export type FeatureBlocks = Readonly<Record<string, AnyBlock>>;

/** The `permissions` constant of `blocks.generated.ts`. */
export type FeaturePermissions = Readonly<
  Record<string, Readonly<Record<string, string>>>
>;

/** A block whose client loads the caller's keys, such as the access block. */
export interface PermissionsBlock extends AnyBlock {
  readonly create:
    | ((options: never) => {
        permissions(keys: readonly string[]): AsyncResult<PermissionSet>;
      })
    | undefined;
}

/** What `defineRecordFeature` takes. */
export interface RecordFeatureSpec<T extends string, B extends FeatureBlocks> {
  /** The subject type, such as `"customer"`. */
  readonly type: T;
  /** The blocks whose sections the record page shows. */
  readonly blocks: B;
  /** `blockConfig` from `blocks.generated.ts`. */
  readonly config?: GeneratedBlocks;
  /**
   * `permissions` from `blocks.generated.ts`, which maps each section's actions
   * to the keys the `can` flags check.
   */
  readonly permissions?: FeaturePermissions;
  /**
   * The access block, which loads the caller's keys for the `can` flags.
   * Without it every flag is `true` and RLS decides.
   */
  readonly access?: PermissionsBlock;
}

/**
 * One subject's record page: its sections, the writes each one takes, and what
 * the caller may do. `gen` writes one per subject (`generateFeatures`); the
 * framework bindings (`recordServer`, `recordQueries`, `createRecordProvider`)
 * take it.
 */
export interface RecordFeature<
  T extends string = string,
  B extends FeatureBlocks = FeatureBlocks,
> extends RecordFeatureSpec<T, B> {
  /** Every section the blocks declare; the first block wins a name. */
  readonly sections: readonly SectionName<B>[];
}

/** Describes one subject's record page from the blocks that own its sections. */
export function defineRecordFeature<
  const T extends string,
  const B extends FeatureBlocks,
>(spec: RecordFeatureSpec<T, B>): RecordFeature<T, B> {
  const seen = new Set<string>();

  for (const block of Object.values(spec.blocks)) {
    for (const name of Object.keys(block.sections ?? {})) {
      seen.add(name);
    }
  }

  // SAFETY: every name comes from one of `B`'s sections.
  return { ...spec, sections: [...seen] as SectionName<B>[] };
}

/** The record a feature's page shows. */
export function recordSubject<T extends string>(
  feature: { readonly type: T },
  id: string,
): SubjectRef<T> {
  return { type: feature.type, id };
}

/** The writes of the section named `S`, by name. */
export type SectionWritesOf<
  B extends FeatureBlocks,
  S extends string,
> = SectionWriteName<SectionNamed<B, S>>;

/** What the caller may do on each section: `read` and one flag per write. */
export type RecordCan<B extends FeatureBlocks, N extends string> = {
  readonly [S in N]: { readonly read: boolean } & {
    readonly [W in SectionWritesOf<B, S>]: boolean;
  };
};

interface WriteFound {
  readonly key: string;
  readonly module: string;
  readonly write: AnySectionWrite;
  readonly permission: string | undefined;
}

/** The block key, module and write that `section.write` names. */
export function findSectionWrite(
  feature: Pick<RecordFeature, "blocks">,
  section: string,
  write: string,
): WriteFound | undefined {
  const found = findSection(feature.blocks, section);
  const entry = found?.section.writes?.[write];

  return found === undefined || entry === undefined
    ? undefined
    : {
        key: found.key,
        module: found.module,
        write: entry,
        permission: entry.permission ?? found.section.permissions.write,
      };
}

function keyOf(
  feature: Pick<RecordFeature, "permissions">,
  module: string,
  action: string | undefined,
): string | undefined {
  return action === undefined
    ? undefined
    : feature.permissions?.[module]?.[action];
}

/**
 * The permission keys a feature's sections check, for one
 * `access.permissions(keys)` call.
 */
export function recordPermissionKeys(
  feature: Pick<RecordFeature, "blocks" | "permissions"> & {
    readonly sections: readonly string[];
  },
): readonly string[] {
  const keys = new Set<string>();

  for (const name of feature.sections) {
    const found = findSection(feature.blocks, name);

    if (found === undefined) {
      continue;
    }

    const { permissions, writes = {} } = found.section;

    const actions = [
      permissions.read,
      ...Object.values(writes).map(
        (write) => write.permission ?? permissions.write,
      ),
    ];

    for (const action of actions) {
      const key = keyOf(feature, found.module, action);

      if (key !== undefined) {
        keys.add(key);
      }
    }
  }

  return [...keys];
}

/**
 * What the caller may do on each of a feature's sections, from its
 * `PermissionSet`. A section action with no key in `permissions` is allowed,
 * and so is everything when `set` is `undefined` (no access block): RLS and
 * each function's checks decide.
 */
export function recordCan<B extends FeatureBlocks, N extends SectionName<B>>(
  feature: Pick<RecordFeature<string, B>, "blocks" | "permissions"> & {
    readonly sections: readonly N[];
  },
  set: PermissionSet | null | undefined,
): RecordCan<B, N> {
  const allowed = (module: string, action: string | undefined): boolean => {
    if (set === undefined) {
      return true;
    }

    const key = keyOf(feature, module, action);

    return key === undefined || holds(set, key);
  };

  // SAFETY: one entry per section name, with `read` and one flag per write,
  // as `RecordCan` maps them.
  return Object.fromEntries(
    feature.sections.flatMap((name) => {
      const found = findSection(feature.blocks, name);

      if (found === undefined) {
        return [];
      }

      const { permissions, writes = {} } = found.section;

      return [
        [
          name,
          {
            read: allowed(found.module, permissions.read),
            ...Object.fromEntries(
              Object.entries(writes).map(([write, entry]) => [
                write,
                allowed(found.module, entry.permission ?? permissions.write),
              ]),
            ),
          },
        ],
      ];
    }),
  ) as RecordCan<B, N>;
}

/** The write names of each of a feature's sections. */
export function featureWrites(
  feature: Pick<RecordFeature, "blocks"> & {
    readonly sections: readonly string[];
  },
): readonly (readonly [section: string, writes: readonly string[]])[] {
  return feature.sections.map((section) => [
    section,
    Object.keys(findSection(feature.blocks, section)?.section.writes ?? {}),
  ]);
}

/**
 * Runs `section.write` with the client its block's creator made, which
 * `clients` holds under the block's key.
 */
export function runSectionWrite(
  feature: Pick<RecordFeature, "blocks">,
  clients: object,
  section: string,
  write: string,
  subject: SubjectRef,
  input: unknown,
): AsyncResult<unknown> {
  const found = findSectionWrite(feature, section, write);

  // SAFETY: a read of one key of the built blocks.
  const client = (clients as Readonly<Record<string, unknown>>)[
    found?.key ?? ""
  ];

  if (found === undefined || client === undefined) {
    return AsyncResult.err(
      dbError(
        "invalid_request",
        `Section "${section}" has no write "${write}" with its block built`,
      ),
    );
  }

  // SAFETY: the write takes the client its block's creator made and the input
  // its schema validated.
  const run = found.write.run as (
    client: unknown,
    subject: SubjectRef,
    input: unknown,
  ) => AsyncResult<unknown>;

  return run(client, subject, input);
}

/** What a generated write takes: the record's id and the write's input. */
export interface RecordWriteInput<I> {
  readonly id: string;
  readonly input: I;
}

/** The input of one write of a feature's section. */
export type FeatureWriteInput<
  B extends FeatureBlocks,
  S extends string,
  W extends string,
> = SectionWriteInput<SectionNamed<B, S>, W>;

/** What one write of a feature's section resolves to. */
export type FeatureWriteOutput<
  B extends FeatureBlocks,
  S extends string,
  W extends string,
> = SectionWriteOutput<SectionNamed<B, S>, W>;

function isObject(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * A Standard Schema for `{ id, input }`: a non-empty record id and the input
 * `schema` validates, whose issues get the `input` path.
 */
export function recordWriteInput<I>(
  schema: StandardSchemaV1<unknown, I>,
): StandardSchemaV1<unknown, RecordWriteInput<I>> {
  type Out = StandardSchemaV1.Result<RecordWriteInput<I>>;

  const check = (inner: StandardSchemaV1.Result<I>, id: string): Out =>
    inner.issues === undefined
      ? { value: { id, input: inner.value } }
      : {
          issues: inner.issues.map((issue) => ({
            ...issue,
            path: ["input", ...(issue.path ?? [])],
          })),
        };

  return {
    "~standard": {
      version: 1,
      vendor: "better-supabase",
      validate: (value): Out | Promise<Out> => {
        if (!isObject(value)) {
          return { issues: [{ message: "Expected an object" }] };
        }

        const { id, input } = value;

        if (typeof id !== "string" || id === "") {
          return {
            issues: [{ message: "Expected a record id", path: ["id"] }],
          };
        }

        const inner = schema["~standard"].validate(input ?? {});

        return inner instanceof Promise
          ? inner.then((settled) => check(settled, id))
          : check(inner, id);
      },
    },
  };
}

/** A Temporal value, from the runtime or a polyfill. */
interface TemporalValue {
  readonly [Symbol.toStringTag]: `Temporal.${string}`;
  toString(): string;
}

/**
 * `T` with every Temporal value as its ISO 8601 string, so it crosses the
 * Server Component and Server Action boundary.
 */
export type Plain<T> = T extends TemporalValue
  ? string
  : T extends readonly (infer U)[]
    ? Plain<U>[]
    : T extends (...args: never) => unknown
      ? T
      : T extends object
        ? { readonly [K in keyof T]: Plain<T[K]> }
        : T;

function isTemporal(value: object): value is TemporalValue {
  return Object.prototype.toString.call(value).startsWith("[object Temporal.");
}

/**
 * `value` with every Temporal value replaced by its ISO 8601 string, for data
 * passed from a Server Component or returned from a Server Action.
 */
export function plainData<T>(value: T): Plain<T> {
  const walk = (entry: unknown): unknown => {
    if (typeof entry !== "object" || entry === null) {
      return entry;
    }

    if (isTemporal(entry)) {
      return entry.toString();
    }

    if (Array.isArray(entry)) {
      return entry.map(walk);
    }

    return Object.fromEntries(
      Object.entries(entry).map(([key, field]) => [key, walk(field)]),
    );
  };

  // SAFETY: `walk` replaces exactly the Temporal values `Plain` maps to strings.
  return walk(value) as Plain<T>;
}

/** A loaded section with Temporal values as strings. */
export type PlainSection<
  B extends FeatureBlocks,
  S extends string,
> = SectionResult<Plain<SectionData<SectionNamed<B, S>>>>;

/** A feature's loaded sections, by name, with Temporal values as strings. */
export type PlainSections<B extends FeatureBlocks, N extends string> = {
  readonly [S in N]: PlainSection<B, S>;
};
