import type { PermissionSet } from "../blocks/access/permissions.ts";
import type {
  AnySection,
  SectionData,
  SectionOptions,
  SectionResult,
} from "../blocks/sections.ts";
import type { DbError } from "../core/errors.ts";
import type { RecordRef } from "../schema/types.ts";

import { can as holds } from "../blocks/access/permissions.ts";
import { dbError } from "../core/errors.ts";
import { AsyncResult } from "../core/result.ts";

/** Block manifests by the key the app built them under, as `blockSet.blocks`. */
export type SectionBlocks = Readonly<
  Record<
    string,
    {
      readonly sql: readonly string[];
      readonly sections?: Readonly<Record<string, AnySection>>;
    }
  >
>;

/**
 * Where sections come from: the manifests (`blockSet.blocks`) and the clients
 * built from them (`blockSet.create(...)`), keyed alike.
 */
export interface SectionSource<B extends SectionBlocks> {
  readonly blocks: B;
  readonly clients: object;
}

type SectionsIn<Block> = Block extends {
  readonly sections: infer S extends Readonly<Record<string, AnySection>>;
}
  ? S
  : Record<never, never>;

/** Every section name the blocks declare. */
export type SectionName<B extends SectionBlocks> = {
  readonly [K in keyof B]: keyof SectionsIn<B[K]> & string;
}[keyof B];

/** The section a name refers to. */
export type SectionNamed<B extends SectionBlocks, N extends string> = {
  readonly [K in keyof B]: N extends keyof SectionsIn<B[K]>
    ? SectionsIn<B[K]>[N]
    : never;
}[keyof B];

/** The settled results of `loadSections`, by section name. */
export type LoadedSections<B extends SectionBlocks, N extends string> = {
  readonly [K in N]: SectionResult<SectionData<SectionNamed<B, K>>>;
};

/** The permission `loadSections` asks `can` about. */
export interface SectionCheck {
  readonly section: string;
  /** The SQL module whose permission keys `action` names. */
  readonly module: string;
  /** `read`, or the section's `permissions.write` for a write. */
  readonly action: string;
}

export interface LoadSectionsOptions<
  B extends SectionBlocks,
  N extends string,
> {
  /**
   * Whether the caller may see a section; a section it can't is `hidden` and
   * not loaded. Build it with `sectionCan`. Default: every section loads and
   * RLS decides what it returns.
   */
  readonly can?: (check: SectionCheck) => boolean;
  /** Options for each section's `load`, such as `{ comments: { limit: 20 } }`. */
  readonly options?: {
    readonly [K in N]?: SectionOptions<SectionNamed<B, K>>;
  };
}

interface Found {
  readonly key: string;
  readonly module: string;
  readonly section: AnySection;
}

/** The block key, module and section a section name refers to. */
export function findSection(
  blocks: SectionBlocks,
  name: string,
): Found | undefined {
  for (const [key, block] of Object.entries(blocks)) {
    const section = block.sections?.[name];

    if (section !== undefined) {
      return { key, module: section.module ?? block.sql[0] ?? key, section };
    }
  }

  return undefined;
}

function clientOf(clients: object, key: string): unknown {
  // SAFETY: a read of one key of the built blocks.
  return (clients as Readonly<Record<string, unknown>>)[key];
}

function missing(name: string, detail: string): DbError {
  return dbError("invalid_request", `Section "${name}" ${detail}`);
}

/**
 * A `can` for `loadSections` from the caller's `PermissionSet` and the
 * `permissions` constant of `blocks.generated.ts`: a section needs the key its
 * module's action names there. An action with no key there is allowed, and RLS
 * decides.
 */
export function sectionCan(
  set: PermissionSet | null | undefined,
  permissions: Readonly<Record<string, Readonly<Record<string, string>>>>,
): (check: SectionCheck) => boolean {
  return ({ module, action }) => {
    const key = permissions[module]?.[action];

    return key === undefined || holds(set, key);
  };
}

/**
 * Loads a record's sections in parallel, each one settled: `ok` with its rows,
 * `error` with a `DbError`, or `hidden` when `can` says the caller can't read
 * it, which never runs its query. It never throws.
 *
 * ```ts
 * const { comments, tags } = await loadSections(
 *   { blocks: blockSet.blocks, clients: blocks },
 *   { type: "customer", id },
 *   ["comments", "tags"],
 *   { can: sectionCan(permissionSet, permissions) },
 * );
 * ```
 */
export async function loadSections<
  B extends SectionBlocks,
  const N extends SectionName<B>,
>(
  source: SectionSource<B>,
  subject: RecordRef,
  names: readonly N[],
  options: LoadSectionsOptions<B, N> = {},
): Promise<LoadedSections<B, N>> {
  const settled = await Promise.all(
    names.map(async (name): Promise<[N, SectionResult<unknown>]> => {
      const found = findSection(source.blocks, name);

      if (found === undefined) {
        return [
          name,
          { kind: "error", error: missing(name, "is in no block") },
        ];
      }

      const allowed =
        options.can?.({
          section: name,
          module: found.module,
          action: found.section.permissions.read,
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

      // SAFETY: the section takes the client its block's creator made and the
      // options `LoadSectionsOptions` typed for it.
      const load = found.section.load as (
        client: unknown,
        subject: RecordRef,
        options: unknown,
      ) => AsyncResult<unknown>;

      // SAFETY: a read of one key of the options typed by section name.
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

  // SAFETY: one settled result per name, each with the data its section loads.
  return Object.fromEntries(settled) as LoadedSections<B, N>;
}

/**
 * How many rows a section has for each of `subjects`, keyed by `subjectKey`
 * (`type:id`), for a badge on each row of a list. A section without `count`
 * fails with `unsupported`.
 */
export function countSection<B extends SectionBlocks>(
  source: SectionSource<B>,
  name: SectionName<B>,
  subjects: readonly RecordRef[],
): AsyncResult<Readonly<Record<string, number>>> {
  const found = findSection(source.blocks, name);
  const client = found && clientOf(source.clients, found.key);

  if (found?.section.count === undefined || client === undefined) {
    return AsyncResult.err(
      dbError("unsupported", `Section "${name}" can't count rows`),
    );
  }

  // SAFETY: the section takes the client its block's creator made.
  const count = found.section.count as (
    client: unknown,
    subjects: readonly RecordRef[],
  ) => AsyncResult<Readonly<Record<string, number>>>;

  return count(client, subjects);
}
