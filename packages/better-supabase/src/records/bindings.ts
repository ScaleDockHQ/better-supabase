import type { PermissionSet } from "../blocks/permissions/permissions-controller.ts";
import type {
  AnyRecordBinding,
  RecordBindingData,
  RecordBindingOptions,
  RecordBindingResult,
} from "../blocks/record-bindings.ts";
import type { DbError } from "../core/errors.ts";
import type { RecordRef } from "../schema/types.ts";

import { can as holds } from "../blocks/permissions/permissions-controller.ts";
import { dbError } from "../core/errors.ts";
import { AsyncResult } from "../core/result.ts";

/** Block manifests by the key the app built them under, as `blockSet.blocks`. */
export type BindingBlocks = Readonly<
  Record<
    string,
    {
      readonly sql: readonly string[];
      readonly record?: AnyRecordBinding | undefined;
    }
  >
>;

/**
 * Where bindings come from: the manifests (`blockSet.blocks`) and the clients
 * built from them (`blockSet.create(...)`), keyed alike.
 */
export interface BindingSource<B extends BindingBlocks> {
  readonly blocks: B;
  readonly clients: object;
}

/** The keys of the blocks that bind to a record. */
export type BindingName<B extends BindingBlocks> = {
  readonly [K in keyof B]: B[K] extends { readonly record: AnyRecordBinding }
    ? K & string
    : never;
}[keyof B];

/** The record binding of the block under key `N`. */
export type BindingOf<
  B extends BindingBlocks,
  N extends string,
> = N extends keyof B
  ? B[N] extends { readonly record: infer R extends AnyRecordBinding }
    ? R
    : never
  : never;

/** The settled results of `loadBindings`, by binding name. */
export type LoadedBindings<B extends BindingBlocks, N extends string> = {
  readonly [K in N]: RecordBindingResult<RecordBindingData<BindingOf<B, K>>>;
};

/** The permission `loadBindings` asks `can` about. */
export interface BindingCheck {
  /** The key of the block whose binding it is. */
  readonly binding: string;
  /** The SQL module whose permission keys `action` names. */
  readonly module: string;
  /** `read`, or the binding's `permissions.write` for a write. */
  readonly action: string;
}

export interface LoadBindingsOptions<
  B extends BindingBlocks,
  N extends string,
> {
  /**
   * Whether the caller may see a binding; a binding it can't is `hidden` and
   * not loaded. Build it with `bindingCan`. Default: every binding loads and
   * RLS decides what it returns.
   */
  readonly can?: (check: BindingCheck) => boolean;
  /** Options for each binding's `load`, such as `{ comments: { limit: 20 } }`. */
  readonly options?: {
    readonly [K in N]?: RecordBindingOptions<BindingOf<B, K>>;
  };
}

interface Found {
  readonly key: string;
  readonly module: string;
  readonly binding: AnyRecordBinding;
}

/** The block key, module and binding a binding name refers to. */
export function findBinding(
  blocks: BindingBlocks,
  name: string,
): Found | undefined {
  const binding = blocks[name]?.record;

  return binding === undefined
    ? undefined
    : {
        key: name,
        module: binding.module ?? blocks[name]?.sql[0] ?? name,
        binding,
      };
}

function clientOf(clients: object, key: string): unknown {
  // SAFETY: a read of one key of the built blocks.
  return (clients as Readonly<Record<string, unknown>>)[key];
}

function missing(name: string, detail: string): DbError {
  return dbError("invalid_request", `Record binding "${name}" ${detail}`);
}

/**
 * A `can` for `loadBindings` from the caller's `PermissionSet` and the
 * `permissions` constant of `blocks.generated.ts`: a binding needs the key its
 * module's action names there. An action with no key there is allowed, and RLS
 * decides.
 */
export function bindingCan(
  set: PermissionSet | null | undefined,
  permissions: Readonly<Record<string, Readonly<Record<string, string>>>>,
): (check: BindingCheck) => boolean {
  return ({ module, action }) => {
    const key = permissions[module]?.[action];

    return key === undefined || holds(set, key);
  };
}

/**
 * Loads a record's bindings in parallel, each one settled: `ok` with its rows,
 * `error` with a `DbError`, or `hidden` when `can` says the caller can't read
 * it, which never runs its query. It never throws.
 *
 * ```ts
 * const { comments, tags } = await loadBindings(
 *   { blocks: blockSet.blocks, clients: blocks },
 *   { type: "customer", id },
 *   ["comments", "tags"],
 *   { can: bindingCan(permissionSet, permissions) },
 * );
 * ```
 */
export async function loadBindings<
  B extends BindingBlocks,
  const N extends BindingName<B>,
>(
  source: BindingSource<B>,
  subject: RecordRef,
  names: readonly N[],
  options: LoadBindingsOptions<B, N> = {},
): Promise<LoadedBindings<B, N>> {
  const settled = await Promise.all(
    names.map(async (name): Promise<[N, RecordBindingResult<unknown>]> => {
      const found = findBinding(source.blocks, name);

      if (found === undefined) {
        return [
          name,
          { kind: "error", error: missing(name, "is in no block") },
        ];
      }

      const allowed =
        options.can?.({
          binding: name,
          module: found.module,
          action: found.binding.permissions.read,
        }) ?? true;

      if (!allowed) {
        return [name, { kind: "hidden" }];
      }

      const client = clientOf(source.clients, found.key);

      if (client === undefined) {
        return [
          name,
          {
            kind: "error",
            error: missing(name, `needs the "${found.key}" block built`),
          },
        ];
      }

      // SAFETY: the binding takes the client its block's creator made and the
      // options `LoadBindingsOptions` typed for it.
      const load = found.binding.load as (
        client: unknown,
        subject: RecordRef,
        options: unknown,
      ) => AsyncResult<unknown>;

      // SAFETY: a read of one key of the options typed by binding name.
      const given = (
        options.options as Readonly<Record<string, unknown>> | undefined
      )?.[name];

      const result = await load(client, subject, given);

      return [
        name,
        result.ok
          ? { kind: "ok", data: result.data }
          : { kind: "error", error: result.error },
      ];
    }),
  );

  // SAFETY: one settled result per name, each with the data its binding loads.
  return Object.fromEntries(settled) as LoadedBindings<B, N>;
}

/**
 * How many rows a binding has for each of `subjects`, keyed by `subjectKey`
 * (`type:id`), for a badge on each row of a list. A binding without `count`
 * fails with `unsupported`.
 */
export function countBinding<B extends BindingBlocks>(
  source: BindingSource<B>,
  name: BindingName<B>,
  subjects: readonly RecordRef[],
): AsyncResult<Readonly<Record<string, number>>> {
  const found = findBinding(source.blocks, name);
  const client = found && clientOf(source.clients, found.key);

  if (found?.binding.count === undefined || client === undefined) {
    return AsyncResult.err(
      dbError("unsupported", `Record binding "${name}" can't count rows`),
    );
  }

  // SAFETY: the binding takes the client its block's creator made.
  const count = found.binding.count as (
    client: unknown,
    subjects: readonly RecordRef[],
  ) => AsyncResult<Readonly<Record<string, number>>>;

  return count(client, subjects);
}
