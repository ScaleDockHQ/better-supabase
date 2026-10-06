import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { FlagDefinition, FlagRule, FlagType, FlagValue } from "./flags.ts";

import { blockCall } from "../shared.ts";
import { flagDefinitionsOf } from "./flags.ts";

export interface FlagAdminOptions {
  /**
   * The caller's transport: `rpcTransport(supabase, { schema: "api" })` for
   * platform staff over the Data API, or a service-role transport.
   */
  readonly transport: BlockTransport;
  /** The module schema (`sql.modules.flags.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

/** The fields `save` writes; the ones left out keep their value. */
export interface FlagInput {
  readonly type?: FlagType;
  readonly description?: string | null;
  readonly variants?: Readonly<Record<string, FlagValue>>;
  readonly defaultVariant?: string;
  readonly enabled?: boolean;
  readonly rules?: readonly FlagRule[];
  /** 0 to 100. */
  readonly rolloutPercentage?: number;
  readonly rolloutVariant?: string | null;
}

/** The override target: one tenant or one user. */
export type FlagOverrideTarget =
  | { readonly organizationId: string; readonly userId?: never }
  | { readonly userId: string; readonly organizationId?: never };

export interface FlagAdmin {
  /** Every flag with its overrides. */
  list(): AsyncResult<readonly FlagDefinition[]>;
  /** Creates or updates a flag; returns it as stored. */
  save(key: string, input: FlagInput): AsyncResult<FlagDefinition | undefined>;
  /** `false` when there was no such flag. */
  remove(key: string): AsyncResult<boolean>;
  /** Sets a tenant's or a user's variant; `null` removes the override. */
  override(
    key: string,
    target: FlagOverrideTarget,
    variant: string | null,
  ): AsyncResult<boolean>;
}

const rowOf = (input: FlagInput): Record<string, unknown> => {
  const row: Record<string, unknown> = {};
  const set = (name: string, value: unknown): void => {
    if (value !== undefined) row[name] = value;
  };
  set("type", input.type);
  set("description", input.description);
  set("variants", input.variants);
  set("default_variant", input.defaultVariant);
  set("enabled", input.enabled);
  set("rules", input.rules);
  set("rollout_percentage", input.rolloutPercentage);
  set("rollout_variant", input.rolloutVariant);
  return row;
};

/**
 * Manages feature flags for platform staff (`flags.manage`) or the service
 * role, through the `flags` module's `list_flags`, `save_flag`,
 * `delete_flag` and `set_flag_override`.
 */
export function createFlagAdmin(options: FlagAdminOptions): FlagAdmin {
  const call = blockCall(options.transport, options.schema, options.mappers);
  return {
    list: () => call("list_flags", {}, flagDefinitionsOf),
    save: (key, input) =>
      call(
        "save_flag",
        { key, definition: rowOf(input) },
        (value) => flagDefinitionsOf(value === null ? [] : [value])[0],
      ),
    remove: (key) => call("delete_flag", { key }, (value) => value === true),
    override: (key, target, variant) =>
      call(
        "set_flag_override",
        {
          key,
          variant,
          tenant: target.organizationId,
          member: target.userId,
        },
        (value) => value === true,
      ),
  };
}
