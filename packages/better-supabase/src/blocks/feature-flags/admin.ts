import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type {
  FlagDefinition,
  FlagRule,
  FlagType,
  FlagValue,
} from "./feature-flags.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import { blockCall } from "../shared.ts";
import { flagDefinitionsOf } from "./feature-flags.ts";

export interface FeatureFlagsOptions<
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
   * (`blocks['feature-flags'].options.extraColumns`), keyed by column name. It
   * types and parses `fields` on `list` and `upsert`, and validates them on
   * `upsert`.
   */
  readonly fields?: S;
  /**
   * `withBlockHooks` hooks around the methods, such as a review rule on
   * `upsert`.
   */
  readonly hooks?: NoInfer<BlockHooks<FeatureFlags<FieldsOf<S>>>>;
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
  readonly rolloutVariant?: string | null;
  /** Values for the extra columns, by column name. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
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
export interface FeatureFlags<F extends object = Record<never, never>> {
  /** Every flag with its overrides. */
  list(): AsyncResult<readonly FlagRecord<F>[]>;
  /** Creates or updates a flag; returns it as stored. */
  upsert(
    key: string,
    input: FlagInput<F>,
  ): AsyncResult<FlagRecord<F> | undefined>;
  /** `false` when there was no such flag. */
  remove(key: string): AsyncResult<boolean>;
  /**
   * Sets the variant of a tenant, a user or a context value; `null` removes the
   * override.
   */
  override(
    key: string,
    target: FlagOverrideTarget,
    variant: string | null,
  ): AsyncResult<boolean>;
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
  set("rollout_variant", input.rolloutVariant);
  set("fields", fields);

  return row;
};

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
export function createFeatureFlags<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: FeatureFlagsOptions<S>): FeatureFlags<FieldsOf<S>> {
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

  const client: FeatureFlags<F> = {
    list: () => call("list_flags", {}, flagDefinitionsOf).andThen(records),
    upsert: (key, input) =>
      AsyncResult.from(() =>
        input.fields === undefined
          ? Promise.resolve(ok(undefined))
          : fields.write({ ...input.fields }),
      )
        .andThen((valid) =>
          call("save_flag", { key, definition: rowOf(input, valid) }, (value) =>
            flagDefinitionsOf(value === null ? [] : [value]),
          ),
        )
        .andThen(records)
        .map((saved) => saved[0]),
    remove: (key) => call("delete_flag", { key }, (value) => value === true),
    override: (key, target, variant) =>
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
  };

  return withBlockHooks(client, options.hooks, {
    block: "feature-flags",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
