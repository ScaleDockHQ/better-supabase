import type { BlockTransport } from "../../core/block-transport.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { AttachmentStorage } from "./attachments.ts";

import { ok } from "../../core/result.ts";
import { blockCall, isRecord, optionalText } from "../shared.ts";
import { stored } from "./attachments.ts";

export interface AttachmentSweeperOptions {
  /**
   * A service-role transport: `queued_attachment_objects()` and
   * `complete_attachment_cleanup()` are granted to `service_role` only.
   */
  readonly transport: BlockTransport;
  /** A service-role `supabase.storage`, to delete the queued objects. */
  readonly storage: AttachmentStorage;
  readonly schema?: string;
}

export interface SweepQueuedOptions {
  /** Objects per sweep, at most 1000. Default 100. */
  readonly limit?: number;
}

export interface SweepResult {
  /** Objects deleted from Storage (or already gone) and dropped from the queue. */
  readonly removed: number;
  /** Objects whose bucket refused the delete; they stay queued. */
  readonly failed: number;
}

export interface AttachmentSweeper {
  /**
   * Deletes the oldest objects `options.offline` queued in `attachment_cleanup`
   * when their records were deleted, and drops them from the queue. Run it from
   * a cron.
   */
  sweepQueued(options?: SweepQueuedOptions): AsyncResult<SweepResult>;
}

interface QueuedObject {
  readonly bucket: string;
  readonly path: string;
}

function queuedOf(value: unknown): readonly QueuedObject[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((item: unknown) => {
    if (!isRecord(item)) {
      return [];
    }

    const bucket = optionalText(item["bucket"]);
    const path = optionalText(item["path"]);

    return bucket === undefined || path === undefined ? [] : [{ bucket, path }];
  });
}

/**
 * Empties the cleanup queue of attachments with `options.offline`: a record
 * deleted while its files could not be (the client went offline, the delete
 * failed) leaves them queued until `sweepQueued` runs.
 */
export function createAttachmentSweeper(
  options: AttachmentSweeperOptions,
): AttachmentSweeper {
  const call = blockCall(options.transport, options.schema);

  return {
    sweepQueued: (sweep = {}) =>
      call(
        "queued_attachment_objects",
        { max_items: sweep.limit ?? 100 },
        queuedOf,
      ).andThen(async (queued) => {
        const byBucket = Map.groupBy(queued, (object) => object.bucket);
        const done: QueuedObject[] = [];
        let failed = 0;

        for (const [bucket, objects] of byBucket) {
          const removed = await stored(
            options.storage
              .from(bucket)
              .remove(objects.map((object) => object.path)),
          );

          if (removed.ok) {
            done.push(...objects);
          } else {
            failed += objects.length;
          }
        }

        if (done.length === 0) {
          return ok({ removed: 0, failed });
        }

        return call("complete_attachment_cleanup", { objects: done }, () => ({
          removed: done.length,
          failed,
        }));
      }),
  };
}
