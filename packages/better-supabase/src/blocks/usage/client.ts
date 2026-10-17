import type { DbError } from "../../core/errors.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { Usage, UsageStatus } from "./usage.ts";

import { defineController, whileSignedIn } from "../controller.ts";

export interface UsageMeterControllerOptions {
  /** `createUsage({ transport })`, or a `Pick` with `overview`. */
  readonly client: Pick<Usage, "overview">;
  readonly auth: AuthPort;
  /** The organization whose usage to read; the meter waits without one. */
  readonly organizationId: string | null;
  /** Only these meters, in this order. Default every meter with usage or a quota. */
  readonly meters?: readonly string[];
}

/** One meter against its quota. */
export interface MeterReading extends UsageStatus {
  /** `used / limit` from 0 to 1, or `undefined` without a limit. */
  readonly fraction: number | undefined;
  /** True once the period's quota is used up. */
  readonly exceeded: boolean;
}

export interface UsageMeterSnapshot {
  /** `undefined` until the first load. */
  readonly meters: readonly MeterReading[] | undefined;
  readonly error: DbError | undefined;
}

export interface UsageMeterActions {
  /** Reads the usage again, such as after the app records some. */
  readonly refresh: () => Promise<void>;
}

export type UsageMeterController = Controller<
  UsageMeterSnapshot,
  UsageMeterActions
>;

function readingOf(status: UsageStatus): MeterReading {
  const limit = status.unlimited ? undefined : status.limit;
  return {
    ...status,
    fraction:
      limit === undefined
        ? undefined
        : limit === 0
          ? 1
          : Math.min(1, status.used / limit),
    exceeded: limit !== undefined && status.used >= limit,
  };
}

/** This period's usage of an organization against its plan's quotas, per meter. */
export function createUsageMeterController(
  options: UsageMeterControllerOptions,
): UsageMeterController {
  const { client, organizationId, meters } = options;
  const pick = (all: readonly UsageStatus[]): readonly UsageStatus[] =>
    meters === undefined
      ? all
      : meters.flatMap((meter) => all.filter((each) => each.meter === meter));
  return defineController<UsageMeterSnapshot, UsageMeterActions>(
    { meters: undefined, error: undefined },
    (state) => {
      const refresh = async (): Promise<void> => {
        if (organizationId === null) {
          return;
        }
        const run = state.run();
        const result = await client.overview(organizationId);
        if (run !== state.run()) {
          return;
        }
        state.set(
          result.ok
            ? { meters: pick(result.data).map(readingOf), error: undefined }
            : { error: result.error },
        );
      };
      return {
        actions: { refresh },
        start: () =>
          organizationId === null
            ? undefined
            : whileSignedIn(options.auth, () => {
                void refresh();
                return;
              }),
      };
    },
  );
}
