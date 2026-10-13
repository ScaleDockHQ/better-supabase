import type { BlockOptions } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { JobHandler } from "../jobs/types.ts";

import { RANK_REBALANCE_QUEUE } from "../../core/rank-keys.ts";
import { blockCall, isRecord, optionalText, textOf } from "../shared.ts";

export type RankOptions = Pick<
  BlockOptions,
  "transport" | "service" | "schema" | "mappers"
>;

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
   * Moves a ranked subject (a `rank` entry in `config.subjects`) as the
   * caller, so the table's policies and any state-machine trigger on the
   * group column apply. Resolves to the row's new key.
   */
  move(
    subjectType: string,
    subjectId: string,
    target: MoveTarget,
  ): AsyncResult<string>;
  /**
   * Rewrites a tenant's keys (in one group, or all of them) to short,
   * evenly spaced keys in the same order. Service only. Resolves to the
   * number of rows rewritten.
   */
  rebalance(
    subjectType: string,
    tenant: string | null,
    group?: string | null,
  ): AsyncResult<number>;
  /** The handler for the `rank.rebalance` queue. */
  readonly job: JobHandler<unknown>;
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
  const rebalance: Rank["rebalance"] = (subjectType, tenant, group) =>
    service(
      "rebalance_ranks",
      { subject_type: subjectType, tenant, rank_group: group ?? null },
      Number,
    );
  return {
    move: (subjectType, subjectId, target) =>
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
    rebalance,
    job: async (payload) => {
      const { subjectType, tenant, group } = payloadOf(payload);
      await rebalance(subjectType, tenant, group).orThrow();
    },
  };
}
