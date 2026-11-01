import type { BlockOptions } from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { RankNeighbors } from "../../core/rank-result.ts";
import type { JobHandler } from "../queue/types.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { RANK_REBALANCE_QUEUE } from "../../core/rank-keys.ts";
import { rankBetweenResult } from "../../core/rank-result.ts";
import { AsyncResult } from "../../core/result.ts";
import { blockCall, isRecord, optionalText, textOf } from "../shared.ts";

export interface RankOptions extends Pick<
  BlockOptions,
  "transport" | "service" | "schema" | "mappers"
> {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Rank>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** Where a row goes: between two rows (by id), and into a group. */
export interface MoveTarget {
  /** The row it goes after, or `null` for the start. */
  readonly previous?: string | null;
  /** The row it goes before, or `null` for the end. */
  readonly next?: string | null;
  /** The group it moves to, such as a pipeline stage. Default: its own. */
  readonly group?: string | null;
}

/** The payload `move` enqueues on `rank.rebalance` when keys grow long. */
export interface RankRebalancePayload {
  readonly subjectType: string;
  readonly tenant: string | null;
  readonly group: string | null;
}

export interface Rank {
  /**
   * Moves a ranked subject (a `rank` entry in `config.subjects`) as the caller,
   * so the table's policies and any state-machine trigger on the group column
   * apply. Resolves to the row's new key.
   */
  move(input: {
    subjectType: string;
    subjectId: string;
    target: MoveTarget;
  }): AsyncResult<string>;
  /**
   * Rewrites a tenant's keys (in one group, or all of them) to short, evenly
   * spaced keys in the same order. Service only. Resolves to the number of rows
   * rewritten.
   */
  rebalance(input: {
    subjectType: string;
    tenant: string | null;
    group?: string | null | undefined;
  }): AsyncResult<number>;
  /** The handler for the `rank.rebalance` queue. */
  readonly job: JobHandler<unknown>;
  /** A key between two neighbors, without a database call. */
  between(input: RankNeighbors): AsyncResult<string>;
}

function payloadOf(value: unknown): RankRebalancePayload {
  if (!isRecord(value)) {
    throw new TypeError(`${RANK_REBALANCE_QUEUE} needs an object payload`);
  }

  return {
    subjectType: textOf(value["subjectType"]),
    tenant: optionalText(value["tenant"]) ?? null,
    group: optionalText(value["group"]) ?? null,
  };
}

export function createRank(options: RankOptions): Rank {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const client: Rank = {
    move: ({ subjectType, subjectId, target }) =>
      call(
        "move",
        {
          subject_type: subjectType,
          subject_id: subjectId,
          previous_id: target.previous ?? null,
          next_id: target.next ?? null,
          to_group: target.group ?? null,
        },
        textOf,
      ),
    rebalance: ({ subjectType, tenant, group }) =>
      service(
        "rebalance_ranks",
        { subject_type: subjectType, tenant, rank_group: group ?? null },
        Number,
      ),
    job: async (payload) => {
      const { subjectType, tenant, group } = payloadOf(payload);
      await hooked.rebalance({ subjectType, tenant, group }).orThrow();
    },
    between: (input) =>
      AsyncResult.from(() => Promise.resolve(rankBetweenResult(input))),
  };

  const hooked = withBlockHooks(client, options.hooks, {
    block: "rank",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
