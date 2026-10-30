import type { BlockCall } from "../../core/block-helpers.ts";
import type {
  AccessRequests,
  RecordAccessRequest,
  RecordRequestListOptions,
} from "../access-requests/access-requests.ts";

import { recordOf } from "../../core/block-helpers.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";

/** What `requestAccess` asks for on a node. */
export interface DriveAccessRequestInput {
  /**
   * One of the actions `driveSubject({ accessRequests })` lists. `read` gives
   * the read role, `comment` the comment role and `write` the write role.
   * Default: `read`.
   */
  readonly action?: "read" | "comment" | "write";
  readonly reason?: string;
  /** How long the grant lasts. Default: 7 days. */
  readonly duration?: Temporal.Duration;
}

/** What `transferOwnership` moved. */
export interface DriveTransfer {
  /** The nodes whose top-role grant moved to the new owner. */
  readonly nodes: number;
  /** The drives the new owner now owns or holds the top role on. */
  readonly drives: number;
}

/** Access requests on nodes and handing a member's items to another. */
export interface DriveAccess {
  /**
   * Asks for access to a node through the access-requests block. The members
   * who may share the node approve it, and the approval grants the role until
   * the duration ends. Needs `driveSubject({ accessRequests })`.
   */
  requestAccess(
    nodeId: string,
    input?: DriveAccessRequestInput,
  ): AsyncResult<RecordAccessRequest>;
  /** The access requests on a node, newest first. */
  accessRequests(
    nodeId: string,
    options?: RecordRequestListOptions,
  ): AsyncResult<readonly RecordAccessRequest[]>;
  /**
   * Gives every item `fromUserId` holds at the top role in the organization to
   * `toUserId`, and the drives they own. Needs `drive.manage`, or the service
   * role.
   */
  transferOwnership(
    organizationId: string,
    fromUserId: string,
    toUserId: string,
  ): AsyncResult<DriveTransfer>;
}

interface DriveAccessOptions {
  readonly call: BlockCall;
  /** The `recordAccess` port, which `createBlocks` passes. */
  readonly recordAccess:
    | Pick<AccessRequests, "requestRecord" | "records">
    | undefined;
  /** `blocks.drive.options.subjectType`. Default: `drive_node`. */
  readonly subjectType: string | undefined;
}

const noRequests = () =>
  dbError(
    "invalid_request",
    "createDrive needs the access-requests block to request access",
    { hint: "DRIVE_ACCESS_REQUESTS_CLIENT" },
  );

function countOf(row: Readonly<Record<string, unknown>>, key: string): number {
  const value = row[key];

  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new TypeError(`drive_transfer_ownership returned no ${key} count`);
  }

  return value;
}

/** The drive client's access request and ownership methods. */
export function driveAccess(options: DriveAccessOptions): DriveAccess {
  const { call, recordAccess } = options;
  const subjectType = options.subjectType ?? "drive_node";

  return {
    requestAccess: (nodeId, input = {}) =>
      recordAccess === undefined
        ? AsyncResult.err(noRequests())
        : recordAccess.requestRecord({
            subjectType,
            subjectId: nodeId,
            ...input,
          }),
    accessRequests: (nodeId, list) =>
      recordAccess === undefined
        ? AsyncResult.err(noRequests())
        : recordAccess.records(subjectType, nodeId, list),
    transferOwnership: (organizationId, fromUserId, toUserId) =>
      call(
        "drive_transfer_ownership",
        { tenant: organizationId, from_user: fromUserId, to_user: toUserId },
        (value) => {
          const row = recordOf(value, "drive_transfer_ownership");

          return {
            nodes: countOf(row, "nodes"),
            drives: countOf(row, "drives"),
          };
        },
      ),
  };
}
