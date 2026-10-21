import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { PermissionSet } from "../blocks/access/permissions.ts";
import type { BlockClientSource } from "../blocks/create-blocks.ts";
import type { AnyBlock } from "../blocks/define-block.ts";
import type { SectionOptions } from "../blocks/sections.ts";
import type { DbError } from "../core/errors.ts";
import type { AsyncResult, Result } from "../core/result.ts";
import type {
  FeatureBlocks,
  FeatureWriteInput,
  FeatureWriteOutput,
  Plain,
  PlainSections,
  RecordCan,
  RecordFeature,
  RecordWriteInput,
  SectionWritesOf,
} from "../records/feature.ts";
import type { SectionName, SectionNamed } from "../records/sections.ts";
import type { SubjectRef } from "../schema/types.ts";
import type { ActionResult } from "../server/kit.ts";

import { createBlockClient } from "../blocks/create-blocks.ts";
import {
  findSectionWrite,
  plainData,
  recordCan,
  recordPermissionKeys,
  recordSubject,
  recordWriteInput,
} from "../records/feature.ts";
import { loadSections } from "../records/sections.ts";
import { invalidateSection, recordTag, sectionTag } from "./records.ts";

/** The context `recordServer` reads: the caller's `Db`. */
export interface RecordServerContext {
  readonly db: BlockClientSource;
}

/**
 * What `recordServer` needs of `bs` (`createNext`): its context and its
 * actions, typed loosely so any app's `bs` fits.
 */
export interface RecordServerHost {
  context(): Promise<RecordServerContext>;
  action<S extends StandardSchemaV1, T>(
    options: { readonly input: S; readonly requireTenant: true },
    fn: (
      input: StandardSchemaV1.InferOutput<S>,
      ctx: RecordServerContext & { readonly tenant: string },
    ) => Promise<T>,
  ): (input: never) => Promise<ActionResult<unknown>>;
}

export interface RecordLoadOptions<
  B extends FeatureBlocks,
  M extends SectionName<B>,
> {
  /** The sections to load. Default: every section of the feature. */
  readonly sections?: readonly M[];
  /** Options for each section's `load`, such as `{ versions: { pageSize: 5 } }`. */
  readonly options?: {
    readonly [K in M]?: SectionOptions<SectionNamed<B, K>>;
  };
}

/** What a generated loader resolves to, safe to pass to a Client Component. */
export interface RecordView<
  T extends string,
  B extends FeatureBlocks,
  N extends string,
  M extends N,
> {
  readonly subject: SubjectRef<T>;
  /** Each requested section settled: `ok`, `error` or `hidden`. */
  readonly sections: PlainSections<B, M>;
  /** What the caller may do on every section of the feature. */
  readonly can: RecordCan<B, N>;
  /**
   * Set when the caller's permissions failed to load; every flag is then
   * `false`.
   */
  readonly permissionsError?: DbError;
}

/** One Server Action per write of each section. */
export type RecordServerActions<B extends FeatureBlocks, N extends string> = {
  readonly [S in N]: {
    readonly [W in SectionWritesOf<B, S>]: (
      input: RecordWriteInput<FeatureWriteInput<B, S, W>>,
    ) => Promise<ActionResult<Plain<FeatureWriteOutput<B, S, W>>>>;
  };
};

export interface RecordServer<
  T extends string,
  B extends FeatureBlocks,
  N extends SectionName<B>,
> {
  /**
   * Loads one record's sections and the caller's flags. It reads the request,
   * so call it outside `"use cache"`: a cached section error would stick.
   */
  load<const M extends N = N>(
    id: string,
    options?: RecordLoadOptions<B, M>,
  ): Promise<RecordView<T, B, N, M>>;
  /** The Server Actions; re-export them from a `"use server"` file. */
  readonly actions: RecordServerActions<B, N>;
  /** The record's cache tag and one per section, scoped to `tenant`. */
  tags(id: string, tenant?: string | null): readonly string[];
}

type Clients = Readonly<Record<string, unknown>>;

function clientsOf(
  feature: Pick<RecordFeature, "blocks" | "config">,
  db: BlockClientSource,
): Clients {
  const options =
    feature.config === undefined ? {} : { config: feature.config };

  return Object.fromEntries(
    Object.entries(feature.blocks).map(([key, block]) => [
      key,
      createBlockClient(db, block, options),
    ]),
  );
}

interface PermissionLoad {
  readonly set: PermissionSet | null | undefined;
  readonly error?: DbError;
}

async function permissionsOf(
  feature: Pick<
    RecordFeature,
    "access" | "blocks" | "config" | "permissions"
  > & { readonly sections: readonly string[] },
  db: BlockClientSource,
): Promise<PermissionLoad> {
  const keys = recordPermissionKeys(feature);

  if (feature.access === undefined || keys.length === 0) {
    return { set: undefined };
  }

  const access = createBlockClient(
    db,
    feature.access,
    feature.config === undefined ? {} : { config: feature.config },
  );

  const result = await access.permissions(keys);

  return result.ok ? { set: result.data } : { set: null, error: result.error };
}

type WriteRun = (
  client: unknown,
  subject: SubjectRef,
  input: unknown,
) => AsyncResult<unknown>;

/**
 * The server half of a generated feature for Next.js: a loader for Server
 * Components and one Server Action per section write. Each action builds the
 * block's client over the caller's `Db` (its tenant), runs the write, and drops
 * the section's and the record's cache tags (`invalidateSection`).
 *
 * ```ts
 * const customer = recordServer(bs, customerFeature);
 * const view = await customer.load(id, { sections: ["comments"] });
 * ```
 */
export function recordServer<
  T extends string,
  B extends FeatureBlocks,
  N extends SectionName<B>,
>(
  bs: RecordServerHost,
  feature: RecordFeature<T, B> & { readonly sections: readonly N[] },
): RecordServer<T, B, N> {
  const actionOf = (section: string, write: string) => {
    const found = findSectionWrite(feature, section, write);

    const block: AnyBlock | undefined =
      found === undefined ? undefined : feature.blocks[found.key];

    if (found === undefined || block === undefined) {
      throw new TypeError(
        `recordServer: section "${section}" has no write "${write}"`,
      );
    }

    const options =
      feature.config === undefined ? {} : { config: feature.config };

    return bs.action(
      { input: recordWriteInput(found.write.input), requireTenant: true },
      async ({ id, input }, ctx): Promise<Result<unknown>> => {
        const client = createBlockClient(ctx.db, block, options);
        const subject = recordSubject(feature, id);
        // SAFETY: the write takes the client its block's creator made and the
        // input its schema validated.
        const run = found.write.run as WriteRun;
        const result = await run(client, subject, input);

        if (!result.ok) {
          return result;
        }

        invalidateSection(subject, section, { tenant: ctx.tenant });

        return { ...result, data: plainData(result.data) };
      },
    );
  };

  // SAFETY: one action per write of each section, as `RecordServerActions`
  // maps them.
  const actions = Object.fromEntries(
    feature.sections.map((section) => {
      const found = Object.keys(
        Object.values(feature.blocks).find(
          (block) => block.sections?.[section] !== undefined,
        )?.sections?.[section]?.writes ?? {},
      );

      return [
        section,
        Object.fromEntries(
          found.map((write) => [write, actionOf(section, write)]),
        ),
      ];
    }),
  ) as RecordServerActions<B, N>;

  return {
    async load(id, options = {}) {
      const ctx = await bs.context();
      const subject = recordSubject(feature, id);
      const permissions = await permissionsOf(feature, ctx.db);
      const can = recordCan(feature, permissions.set);
      // SAFETY: every entry of `RecordCan` has a `read` flag.
      const flags = can as Readonly<Record<string, { readonly read: boolean }>>;

      const readable = new Map(
        Object.entries(flags).map(([name, entry]) => [name, entry.read]),
      );

      // SAFETY: without `sections` the loader loads every section, which is
      // `M` at its default `N`.
      const names = (options.sections ?? feature.sections) as readonly N[];

      const loaded = await loadSections(
        { blocks: feature.blocks, clients: clientsOf(feature, ctx.db) },
        subject,
        names,
        {
          can: ({ section }) => readable.get(section) ?? true,
          // SAFETY: `RecordLoadOptions` types each section's options as
          // `LoadSectionsOptions` does, by section name.
          ...(options.options === undefined
            ? {}
            : { options: options.options as never }),
        },
      );

      // SAFETY: `plainData` maps each section's Temporal values to strings,
      // as `PlainSections` types them.
      return {
        subject,
        sections: plainData(loaded) as never,
        can,
        ...(permissions.error === undefined
          ? {}
          : { permissionsError: permissions.error }),
      };
    },
    actions,
    tags(id, tenant) {
      const subject = recordSubject(feature, id);
      const scope = { tenant };

      return [
        recordTag(subject, scope),
        ...feature.sections.map((section) =>
          sectionTag(subject, section, scope),
        ),
      ];
    },
  };
}
