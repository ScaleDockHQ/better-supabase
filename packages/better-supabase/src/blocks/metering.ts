import type { BlockMethodHooks } from "../core/block-hooks.ts";
import type { DbError } from "../core/errors.ts";
import type { Usage } from "./usage/usage.ts";

import { dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";

/**
 * The one shape of a `quota` option: the usage meter a feature counts against
 * (`blocks.drive.options.quota`). A block option that limits use is named
 * `quota` and takes this.
 */
export interface BlockQuota {
  /** A meter of the `usage` block. */
  readonly meter: string;
  /** What one use counts as. Default 1. */
  readonly quantity?: number;
}

/**
 * What a method declares about a plan limit (`limits` in a manifest). With
 * `createBlocks({ metering: true })` and a `usage` block in the set, the method
 * returns `quota_exceeded` instead of running when the tenant's quota on
 * `meter` can't take `quantity` more. A deliberate gate, unlike a sink, which
 * never changes a result (invariant 5).
 */
export interface MethodLimit extends BlockQuota {
  /**
   * The property of the method's first argument that holds the organization id.
   * Default `organizationId`. A call without one isn't checked.
   */
  readonly tenant?: string;
}

/**
 * What a method declares about the meter it increments (`meters` in a
 * manifest): after a call succeeds, `createBlocks({ metering: true })` records
 * `quantity` on `meter`. A failed call records nothing, and a failed record
 * never changes the result.
 */
export interface MethodMeter extends MethodLimit {
  /** The usage history source. Default `<block>.<method>`. */
  readonly source?: string;
}

/** Method name to its plan limit. */
export type BlockLimits = Readonly<Record<string, MethodLimit>>;

/** Method name to the meter it increments. */
export type BlockMeters = Readonly<Record<string, MethodMeter>>;

/** What `createBlocks` needs from the `usage` block to apply declarations. */
export type MeterPort = Pick<Usage, "canConsume" | "current" | "record">;

type AnyHooks = BlockMethodHooks<unknown[], unknown>;

function tenantOf(args: readonly unknown[], key = "organizationId") {
  const [input] = args;

  const value: unknown = isRecord(input) ? input[key] : undefined;

  return typeof value === "string" ? value : undefined;
}

/** The hooks that apply a block's `limits` and `meters`, by method name. */
export function meteringHooks(
  block: string,
  declared: { limits: BlockLimits; meters: BlockMeters },
  usage: MeterPort,
): Readonly<Record<string, AnyHooks>> {
  const hooks: Record<string, AnyHooks> = {};

  for (const method of new Set([
    ...Object.keys(declared.limits),
    ...Object.keys(declared.meters),
  ])) {
    const limit = declared.limits[method];
    const meter = declared.meters[method];

    hooks[method] = {
      before: async (args): Promise<DbError | void> => {
        const organizationId = tenantOf(args, limit?.tenant);

        if (limit === undefined || organizationId === undefined) {
          return;
        }

        const quantity = limit.quantity ?? 1;

        const fits = await usage.canConsume({
          organizationId,
          meter: limit.meter,
          quantity,
        });

        if (!fits.ok) {
          return fits.error;
        }

        if (fits.data) {
          return;
        }

        const status = await usage.current({
          organizationId,
          meter: limit.meter,
        });

        return dbError(
          "quota_exceeded",
          `The ${limit.meter} limit is reached.`,
          {
            meter: limit.meter,
            ...(status.ok && status.data.limit !== undefined
              ? { limit: status.data.limit }
              : {}),
          },
        );
      },
      after: async (result, args): Promise<void> => {
        const organizationId = tenantOf(args, meter?.tenant);

        if (meter === undefined || !result.ok || organizationId === undefined) {
          return;
        }

        const recorded = await usage.record({
          organizationId,
          meter: meter.meter,
          quantity: meter.quantity ?? 1,
          source: meter.source ?? `${block}.${method}`,
        });

        if (!recorded.ok) {
          throw new Error(recorded.error.message);
        }
      },
    };
  }

  return hooks;
}

/** `first` and `second` as one hook: both `before`s, then both `afters`. */
export function mergeHooks(
  first: AnyHooks | undefined,
  second: AnyHooks | undefined,
): AnyHooks | undefined {
  if (first === undefined || second === undefined) {
    return first ?? second;
  }

  return {
    before: async (args, info) => {
      const refused = await first.before?.(args, info);

      if (refused !== undefined && !Array.isArray(refused)) {
        return refused;
      }

      return second.before?.(Array.isArray(refused) ? refused : args, info);
    },
    after: async (result, args, info) => {
      await first.after?.(result, args, info);
      await second.after?.(result, args, info);
    },
  };
}
