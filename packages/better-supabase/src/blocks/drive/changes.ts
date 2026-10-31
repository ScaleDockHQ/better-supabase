import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";
import type { DriveNode } from "./drive.ts";

import { recordOf, recordsOf, textOf } from "../shared.ts";

/**
 * One entry of the changes feed: a node as it is now, or one that left the
 * tree.
 */
export type DriveChange<N> =
  | { readonly removed: false; readonly node: N }
  | { readonly removed: true; readonly id: string };

/** A page of the changes feed. */
export interface DriveChanges<N> {
  readonly changes: readonly DriveChange<N>[];
  /**
   * Where to continue. Pass it as `cursor` on the next call; it is the cursor
   * you sent when nothing changed.
   */
  readonly cursor: string | undefined;
  /** Whether more changes wait behind this page. */
  readonly more: boolean;
}

/** Options of {@link DriveLifecycle.changes}. */
export interface DriveChangesOptions {
  /** The `cursor` of the previous page; omit it for a full first sync. */
  readonly cursor?: string;
  readonly pageSize?: number;
  /** Only one drive's nodes (with `drives` on). */
  readonly driveId?: string;
}

/** The changes feed and retention sweep of the drive client. */
export interface DriveLifecycle<N> {
  /**
   * The nodes the caller can read that changed after `cursor`, oldest first,
   * for sync clients. A node in the bin comes back as `removed`, and a restore
   * brings it back. A node deleted for good leaves no entry; it was in the bin
   * first, unless an app deleted it directly. Changes from the last few seconds
   * wait for the next call, so a slow transaction isn't skipped.
   */
  changes(
    organizationId: string,
    options?: DriveChangesOptions,
  ): AsyncResult<DriveChanges<N>>;
  /**
   * Service role: moves nodes into the bin when a label on them has a retention
   * policy and the node was last changed longer ago than the policy keeps it.
   * The policy kind is `drive_label_` and the label's name in lower case, with
   * every run of other characters as one underscore (`drive_retention_kind`).
   * Held nodes stay. Returns how many nodes it binned; call it from a
   * schedule.
   */
  sweepRetention(options?: {
    readonly organizationId?: string;
    readonly batchSize?: number;
  }): AsyncResult<number>;
}

export function driveLifecycle(
  call: BlockCall,
  nodeOf: (value: unknown, fn: string) => DriveNode,
): DriveLifecycle<DriveNode> {
  return {
    changes: (organizationId, options = {}) =>
      call(
        "drive_changes",
        {
          tenant: organizationId,
          after: options.cursor ?? null,
          page_size: options.pageSize ?? null,
          drive: options.driveId ?? null,
        },
        (value) => {
          const row = recordOf(value, "drive_changes");
          const cursor = row["cursor"];

          return {
            changes: recordsOf(row["changes"], "drive_changes").map(
              (entry): DriveChange<DriveNode> =>
                entry["removed"] === true
                  ? { removed: true, id: textOf(entry["id"]) }
                  : {
                      removed: false,
                      node: nodeOf(entry["node"], "drive_changes"),
                    },
            ),
            cursor: typeof cursor === "string" ? cursor : undefined,
            more: row["more"] === true,
          };
        },
      ),
    sweepRetention: (options = {}) =>
      call(
        "drive_retention_sweep",
        {
          tenant: options.organizationId ?? null,
          batch_size: options.batchSize ?? null,
        },
        Number,
      ),
  };
}
