import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type {
  FlagCondition,
  FlagContext,
  FlagDefinition,
  FlagRolloutSchedule,
  FlagRule,
  FlagSplit,
  FlagType,
  FlagValue,
} from "./flags.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  blockCall,
  isRecord,
  optionalText,
  recordsOf,
  textOf,
} from "../shared.ts";
import { conditionOf, evaluateFlag, flagDefinitionsOf } from "./flags.ts";

export interface FlagsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> {
  /**
   * The caller's transport: `rpcTransport(supabase, { schema: "api" })` for
   * platform staff over the Data API, or a service-role transport.
   */
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * A Standard Schema for the flag's extra columns
   * (`blocks['flags'].options.extraColumns`), keyed by column name. It types
   * and parses `fields` on `list` and `upsert`, and validates them on
   * `upsert`.
   */
  readonly fields?: S;
  /**
   * `withBlockHooks` hooks around the methods, such as a review rule on
   * `upsert`.
   */
  readonly hooks?: NoInfer<BlockHooks<Flags<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. */
  readonly logger?: Logger;
}

/** The fields `upsert` writes; the ones left out keep their value. */
export interface FlagInput<F extends object = Record<never, never>> {
  readonly type?: FlagType;
  readonly description?: string | null;
  readonly variants?: Readonly<Record<string, FlagValue>>;
  readonly defaultVariant?: string;
  readonly enabled?: boolean;
  /** Archives the flag: it serves its default variant and leaves Flags Explorer. */
  readonly archived?: boolean;
  readonly rules?: readonly FlagRule[];
  /** 0 to 100. */
  readonly rolloutPercentage?: number;
  /** How the rollout splits between variants; `[]` turns the rollout off. */
  readonly rolloutVariants?: readonly FlagSplit[];
  /** A rollout that grows on its own; `null` removes it. */
  readonly rolloutSchedule?: FlagRolloutSchedule | null;
  /** Values for the extra columns, by column name. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

/** One saved state of a flag (`flag_revisions`). */
export interface FlagRevision {
  readonly revision: number;
  /** The flag as `save_flag` left it, in `flag_definitions()` form. */
  readonly definition: FlagDefinition;
  readonly message: string | undefined;
  readonly changedBy: string | undefined;
  /** An ISO 8601 string. */
  readonly changedAt: string;
}

/** A named audience that rules target through `segments`. */
export interface FlagSegment extends FlagCondition {
  readonly name: string;
  readonly description?: string;
}

export interface FlagSaveOptions {
  /** Why the flag changed; kept with the revision. */
  readonly message?: string;
}

/** A flag as staff manage it: its definition and its extra columns. */
export type FlagRecord<F extends object = Record<never, never>> =
  FlagDefinition & {
    /** The extra columns (`options.extraColumns`), by column name. */
    readonly fields: Readonly<Record<string, unknown>> & F;
  };

/** The override target: one tenant, one user or one custom context value. */
export type FlagOverrideTarget =
  | {
      readonly organizationId: string;
      readonly userId?: never;
      readonly context?: never;
    }
  | {
      readonly userId: string;
      readonly organizationId?: never;
      readonly context?: never;
    }
  | {
      /** A custom context, such as `brand`, and its value, such as `acme`. */
      readonly context: string;
      readonly contextKey: string;
      readonly organizationId?: never;
      readonly userId?: never;
    };

/** `F` types the extra columns the `fields` schema describes. */
export interface Flags<F extends object = Record<never, never>> {
  /** Every flag with its overrides. */
  list(): AsyncResult<readonly FlagRecord<F>[]>;
  /** Creates or updates a flag and records a revision; returns it as stored. */
  upsert(
    input: { key: string; input: FlagInput<F> } & FlagSaveOptions,
  ): AsyncResult<FlagRecord<F> | undefined>;
  /** `false` when there was no such flag. Its revisions stay. */
  remove(key: string): AsyncResult<boolean>;
  /** The flag's revisions, newest first. */
  history(key: string): AsyncResult<readonly FlagRevision[]>;
  /**
   * Saves revision `revision` again as a new revision, recreating a deleted
   * flag; `undefined` when there is no such revision.
   */
  restore(input: {
    key: string;
    revision: number;
  }): AsyncResult<FlagRecord<F> | undefined>;
  /** Every segment, by name. */
  segments(): AsyncResult<readonly FlagSegment[]>;
  /** Creates or replaces a segment. */
  saveSegment(segment: FlagSegment): AsyncResult<FlagSegment>;
  /** `false` when there was no such segment; rules naming it stop matching. */
  removeSegment(name: string): AsyncResult<boolean>;
  /**
   * Sets the variant of a tenant, a user or a context value; `null` removes the
   * override.
   */
  override(input: {
    key: string;
    target: FlagOverrideTarget;
    variant: string | null;
  }): AsyncResult<boolean>;
  /**
   * Whether the boolean flag `key` is on for `context` (its tenant, user, roles
   * and plans), evaluated like `flag_evaluation()`. An unknown flag is off. It
   * reads `list`, so a caller who may not list flags gets that error.
   */
  isEnabled(input: {
    key: string;
    context?: FlagContext | undefined;
  }): AsyncResult<boolean>;
  /**
   * The organizations that have `key` turned on through a tenant override, for
   * a staff view of who gets a flag early. A tenant that gets the flag through
   * a rule or the rollout is not listed.
   */
  tenantsWith(input: { key: string }): AsyncResult<readonly string[]>;
}

const rowOf = (
  input: FlagInput,
  fields: Readonly<Record<string, unknown>> | undefined,
): Record<string, unknown> => {
  const row: Record<string, unknown> = {};

  const set = (name: string, value: unknown): void => {
    if (value !== undefined) {
      row[name] = value;
    }
  };

  set("type", input.type);
  set("description", input.description);
  set("variants", input.variants);
  set("default_variant", input.defaultVariant);
  set("enabled", input.enabled);
  set("archived", input.archived);
  set("rules", input.rules);
  set("rollout_percentage", input.rolloutPercentage);
  set("rollout_variants", input.rolloutVariants);
  set("rollout_schedule", input.rolloutSchedule);
  set("fields", fields);

  return row;
};

const segmentRow = (segment: FlagSegment): Record<string, unknown> => {
  const { name, description, ...condition } = segment;

  return { name, description: description ?? null, rules: condition };
};

function segmentsOf(value: unknown): readonly FlagSegment[] {
  return recordsOf(value, "list_flag_segments").flatMap((row) => {
    const name = row["name"];

    if (typeof name !== "string") {
      return [];
    }

    const description = optionalText(row["description"]);

    return [
      {
        name,
        ...(description !== undefined && { description }),
        ...conditionOf(isRecord(row["rules"]) ? row["rules"] : {}),
      },
    ];
  });
}

function revisionsOf(value: unknown): readonly FlagRevision[] {
  return recordsOf(value, "flag_history").flatMap((row) => {
    const stored = row["definition"];

    if (!(isRecord(stored) && typeof stored["key"] === "string")) {
      return [];
    }

    const [definition] = flagDefinitionsOf([stored]);

    return definition
      ? [
          {
            revision: Number(row["revision"]),
            definition,
            message: optionalText(row["message"]),
            changedBy: optionalText(row["changed_by"]),
            changedAt: textOf(row["changed_at"]),
          },
        ]
      : [];
  });
}

const recordOf = async <F extends object>(
  fields: BlockFields<F>,
  flag: FlagDefinition,
) => {
  const parsed = await fields.read({ ...flag.fields });

  return parsed.ok ? ok({ ...flag, fields: parsed.data }) : parsed;
};

/**
 * Manages feature flags for platform staff (`flags.manage`) or the service
 * role, through the `flags` module's `list_flags`, `save_flag`, `delete_flag`
 * and `set_flag_override`.
 */
export function createFlags<S extends StandardSchemaV1 | undefined = undefined>(
  options: FlagsOptions<S>,
): Flags<FieldsOf<S>> {
  type F = FieldsOf<S>;

  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "flag fields");

  const records = (
    flags: readonly FlagDefinition[],
  ): AsyncResult<FlagRecord<F>[]> =>
    AsyncResult.from(async () => {
      const out: FlagRecord<F>[] = [];

      for (const flag of flags) {
        const parsed = await recordOf(fields, flag);

        if (!parsed.ok) {
          return parsed;
        }

        out.push(parsed.data);
      }

      return ok(out);
    });

  const single = (value: unknown): readonly FlagDefinition[] =>
    flagDefinitionsOf(value === null ? [] : [value]);

  const client: Flags<F> = {
    list: () => call("list_flags", {}, flagDefinitionsOf).andThen(records),
    upsert: ({ key, input, ...saveOptions }) =>
      AsyncResult.from(() =>
        input.fields === undefined
          ? Promise.resolve(ok(undefined))
          : fields.write({ ...input.fields }),
      )
        .andThen((valid) =>
          call(
            "save_flag",
            {
              key,
              definition: rowOf(input, valid),
              ...(saveOptions.message === undefined
                ? {}
                : { message: saveOptions.message }),
            },
            single,
          ),
        )
        .andThen(records)
        .map((saved) => saved[0]),
    remove: (key) => call("delete_flag", { key }, (value) => value === true),
    history: (key) => call("flag_history", { key }, revisionsOf),
    restore: ({ key, revision }) =>
      call("restore_flag", { key, revision }, single)
        .andThen(records)
        .map((saved) => saved[0]),
    segments: () => call("list_flag_segments", {}, segmentsOf),
    saveSegment: (segment) =>
      call("save_flag_segment", segmentRow(segment), (value) => {
        const [saved] = segmentsOf([value]);

        return saved ?? segment;
      }),
    removeSegment: (name) =>
      call("delete_flag_segment", { name }, (value) => value === true),
    override: ({ key, target, variant }) =>
      call(
        "set_flag_override",
        {
          key,
          variant,
          tenant: target.organizationId,
          member: target.userId,
          ...(target.context !== undefined && {
            context: target.context,
            context_key: target.contextKey,
          }),
        },
        (value) => value === true,
      ),
    isEnabled: ({ key, context }) =>
      hooked.list().andThen(async (flags) => {
        const flag = flags.find((each) => each.key === key);

        if (flag?.type !== "boolean") {
          return ok(false);
        }

        const evaluation = await evaluateFlag(flag, context ?? {});

        return ok(evaluation.value === true);
      }),
    tenantsWith: ({ key }) =>
      hooked.list().map((flags) => {
        const flag = flags.find((each) => each.key === key);

        return [
          ...new Set(
            (flag?.overrides ?? []).flatMap((override) =>
              override.organizationId !== undefined &&
              flag?.variants[override.variant] === true
                ? [override.organizationId]
                : [],
            ),
          ),
        ];
      }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Flags<F> = withBlockHooks(client, options.hooks, {
    block: "flags",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
