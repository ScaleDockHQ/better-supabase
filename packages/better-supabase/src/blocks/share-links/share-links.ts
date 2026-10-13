import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

import { blockCall, recordOf, textOf } from "../shared.ts";

export interface ShareLinksOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface CreatedShareLink {
  readonly id: string;
  /** Returned once. Later calls only see the hash. */
  readonly token: string;
}

export interface ShareLinks {
  create(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    role?: string,
  ): AsyncResult<CreatedShareLink>;
  revoke(id: string): AsyncResult<boolean>;
  resolve(token: string): AsyncResult<unknown>;
  recordView(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    viewerKind: string,
    viewer?: string,
  ): AsyncResult<boolean>;
  list(subjectType: string, subjectId: string): AsyncResult<unknown>;
  setState(
    subjectType: string,
    subjectId: string,
    starred: boolean,
  ): AsyncResult<boolean>;
}

export function createShareLinks(options: ShareLinksOptions): ShareLinks {
  const call = blockCall(options.transport, options.schema, options.mappers);
  return {
    create: (organizationId, subjectType, subjectId, role) =>
      call(
        "create_share_link",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          role: role ?? "view",
        },
        (value) => {
          const row = recordOf(value, "create_share_link");
          return { id: textOf(row["id"]), token: textOf(row["token"]) };
        },
      ),
    revoke: (id) =>
      call("revoke_share_link", { id }, (value) => value === true),
    resolve: (token) => call("resolve_share_link", { token }, (value) => value),
    recordView: (organizationId, subjectType, subjectId, viewerKind, viewer) =>
      call(
        "record_view",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          viewer_kind: viewerKind,
          viewer: viewer ?? null,
        },
        (value) => value === true,
      ),
    list: (subjectType, subjectId) =>
      call(
        "list_share_links",
        { subject_type: subjectType, subject_id: subjectId },
        (value) => value,
      ),
    setState: (subjectType, subjectId, starred) =>
      call(
        "set_user_state",
        { subject_type: subjectType, subject_id: subjectId, starred },
        (value) => value === true,
      ),
  };
}
