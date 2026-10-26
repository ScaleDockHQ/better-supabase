import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { GeneratedBlocks } from "../blocks/block-config.ts";
import type { AnyBlock } from "../blocks/define-block.ts";
import type { PermissionSet } from "../blocks/permissions/permissions-controller.ts";
import type {
  AnyRecordBindingWrite,
  RecordBindingData,
  RecordBindingResult,
  RecordBindingWriteInput,
  RecordBindingWriteName,
  RecordBindingWriteOutput,
} from "../blocks/record-bindings.ts";
import type { RecordRef } from "../schema/types.ts";
import type { BindingName, BindingOf } from "./bindings.ts";

import { can as holds } from "../blocks/permissions/permissions-controller.ts";
import { dbError } from "../core/errors.ts";
import { AsyncResult } from "../core/result.ts";
import { findBinding } from "./bindings.ts";

/** The binding blocks of a record type, keyed like `blockSet.blocks`. */
export type RecordTypeBlocks = Readonly<Record<string, AnyBlock>>;

/** The `permissions` constant of `blocks.generated.ts`. */
export type RecordTypePermissions = Readonly<
  Record<string, Readonly<Record<string, string>>>
>;

/** A block whose client loads the caller's keys, such as the permissions block. */
export interface PermissionsBlock extends AnyBlock {
  readonly create:
    | ((options: never) => {
        permissions(keys: readonly string[]): AsyncResult<PermissionSet>;
      })
    | undefined;
}

/** What `defineRecordType` takes. */
export interface RecordTypeSpec<T extends string, B extends RecordTypeBlocks> {
  /** The subject type, such as `"customer"`. */
  readonly type: T;
  /** The blocks whose bindings the record page shows. */
  readonly blocks: B;
  /** `blockConfig` from `blocks.generated.ts`. */
  readonly config?: GeneratedBlocks;
  /**
   * `permissions` from `blocks.generated.ts`, which maps each binding's actions
   * to the keys the `can` flags check.
   */
  readonly permissions?: RecordTypePermissions;
  /**
   * The permissions block, which loads the caller's keys for the `can` flags.
   * Without it every flag is `true` and RLS decides.
   */
  readonly access?: PermissionsBlock;
}

/**
 * One record type's page: the blocks that bind to it, the writes each binding
 * takes, and what the caller may do. `gen` writes one per record type to
 * `records/<type>.ts` (`gen.recordTypes`); `bsb.record`, `recordQueries` and
 * `createRecordProvider` take it.
 */
export interface RecordType<
  T extends string = string,
  B extends RecordTypeBlocks = RecordTypeBlocks,
> extends RecordTypeSpec<T, B> {
  /** The keys of the blocks that bind to the record. */
  readonly bindings: readonly BindingName<B>[];
}

/** Describes one subject's record page from the blocks that own its bindings. */
export function defineRecordType<
  const T extends string,
  const B extends RecordTypeBlocks,
>(spec: RecordTypeSpec<T, B>): RecordType<T, B> {
  const bindings = Object.entries(spec.blocks).flatMap(([key, block]) =>
    block.record === undefined ? [] : [key],
  );

  // SAFETY: every key names a block of `B` with a record binding.
  return { ...spec, bindings: bindings as BindingName<B>[] };
}

/** The record a record type's page shows. */
export function recordSubject<T extends string>(
  feature: { readonly type: T },
  id: string,
): RecordRef<T> {
  return { type: feature.type, id };
}

/** The writes of the binding named `S`, by name. */
export type BindingWritesOf<
  B extends RecordTypeBlocks,
  S extends string,
> = RecordBindingWriteName<BindingOf<B, S>>;

/** What the caller may do on each binding: `read` and one flag per write. */
export type RecordCan<B extends RecordTypeBlocks, N extends string> = {
  readonly [S in N]: { readonly read: boolean } & {
    readonly [W in BindingWritesOf<B, S>]: boolean;
  };
};

interface WriteFound {
  readonly key: string;
  readonly module: string;
  readonly write: AnyRecordBindingWrite;
  readonly permission: string | undefined;
}

/** The block key, module and write that `binding.write` names. */
export function findBindingWrite(
  feature: Pick<RecordType, "blocks">,
  binding: string,
  write: string,
): WriteFound | undefined {
  const found = findBinding(feature.blocks, binding);
  const entry = found?.binding.writes?.[write];

  return found === undefined || entry === undefined
    ? undefined
    : {
        key: found.key,
        module: found.module,
        write: entry,
        permission: entry.permission ?? found.binding.permissions.write,
      };
}

function keyOf(
  feature: Pick<RecordType, "permissions">,
  module: string,
  action: string | undefined,
): string | undefined {
  return action === undefined
    ? undefined
    : feature.permissions?.[module]?.[action];
}

/**
 * The permission keys a record type's bindings check, for one
 * `access.permissions(keys)` call.
 */
export function recordPermissionKeys(
  feature: Pick<RecordType, "blocks" | "permissions"> & {
    readonly bindings: readonly string[];
  },
): readonly string[] {
  const keys = new Set<string>();

  for (const name of feature.bindings) {
    const found = findBinding(feature.blocks, name);

    if (found === undefined) {
      continue;
    }

    const { permissions, writes = {} } = found.binding;

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
 * What the caller may do on each of a record type's bindings, from its
 * `PermissionSet`. A binding action with no key in `permissions` is allowed,
 * and so is everything when `set` is `undefined` (no permissions block): RLS
 * and each function's checks decide.
 */
export function recordCan<B extends RecordTypeBlocks, N extends BindingName<B>>(
  feature: Pick<RecordType<string, B>, "blocks" | "permissions"> & {
    readonly bindings: readonly N[];
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

  // SAFETY: one entry per binding name, with `read` and one flag per write,
  // as `RecordCan` maps them.
  return Object.fromEntries(
    feature.bindings.flatMap((name) => {
      const found = findBinding(feature.blocks, name);

      if (found === undefined) {
        return [];
      }

      const { permissions, writes = {} } = found.binding;

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

/** The write names of each of a record type's bindings. */
export function bindingWrites(
  feature: Pick<RecordType, "blocks"> & {
    readonly bindings: readonly string[];
  },
): readonly (readonly [binding: string, writes: readonly string[]])[] {
  return feature.bindings.map((binding) => [
    binding,
    Object.keys(findBinding(feature.blocks, binding)?.binding.writes ?? {}),
  ]);
}

/**
 * Runs `binding.write` with the client its block's creator made, which
 * `clients` holds under the block's key.
 */
export function runBindingWrite(
  feature: Pick<RecordType, "blocks">,
  clients: object,
  binding: string,
  write: string,
  subject: RecordRef,
  input: unknown,
): AsyncResult<unknown> {
  const found = findBindingWrite(feature, binding, write);

  // SAFETY: a read of one key of the built blocks.
  const client = (clients as Readonly<Record<string, unknown>>)[
    found?.key ?? ""
  ];

  if (found === undefined || client === undefined) {
    return AsyncResult.err(
      dbError(
        "invalid_request",
        `Record binding "${binding}" has no write "${write}" with its block built`,
      ),
    );
  }

  // SAFETY: the write takes the client its block's creator made and the input
  // its schema validated.
  const run = found.write.run as (
    client: unknown,
    subject: RecordRef,
    input: unknown,
  ) => AsyncResult<unknown>;

  return run(client, subject, input);
}

/** What a generated write takes: the record's id and the write's input. */
export interface RecordWriteInput<I> {
  readonly id: string;
  readonly input: I;
}

/** The input of one write of a record type's binding. */
export type RecordTypeWriteInput<
  B extends RecordTypeBlocks,
  S extends string,
  W extends string,
> = RecordBindingWriteInput<BindingOf<B, S>, W>;

/** What one write of a record type's binding resolves to. */
export type RecordTypeWriteOutput<
  B extends RecordTypeBlocks,
  S extends string,
  W extends string,
> = RecordBindingWriteOutput<BindingOf<B, S>, W>;

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

/** A loaded binding with Temporal values as strings. */
export type PlainBinding<
  B extends RecordTypeBlocks,
  S extends string,
> = RecordBindingResult<Plain<RecordBindingData<BindingOf<B, S>>>>;

/** A record type's loaded bindings, by name, with Temporal values as strings. */
export type PlainBindings<B extends RecordTypeBlocks, N extends string> = {
  readonly [S in N]: PlainBinding<B, S>;
};
