import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

import { blockCall, optionalText, recordOf, textOf } from "../shared.ts";

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

export interface CreateShareLinkOptions {
  /** `view` unless set. */
  readonly role?: string;
  /**
   * Pins the link to one of the subject's versions (the versions module),
   * which `versions.getShared(token)` reads for anon.
   */
  readonly versionId?: string;
}

/** What a live token points at. */
export interface ResolvedShareLink {
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly role: string;
  /** The version the link is pinned to, when it has one. */
  readonly versionId?: string;
}

export interface ShareLinks {
  /** A role string is the same as `{ role }`. */
  create(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    options?: string | CreateShareLinkOptions,
  ): AsyncResult<CreatedShareLink>;
  revoke(id: string): AsyncResult<boolean>;
  /** `null` for an unknown, revoked or expired token. */
  resolve(token: string): AsyncResult<ResolvedShareLink | null>;
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
    create: (organizationId, subjectType, subjectId, options = {}) => {
      const { role, versionId } =
        typeof options === "string"
          ? { role: options, versionId: undefined }
          : options;
      return call(
        "create_share_link",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          role: role ?? "view",
          version_id: versionId ?? null,
        },
        (value) => {
          const row = recordOf(value, "create_share_link");
          return { id: textOf(row["id"]), token: textOf(row["token"]) };
        },
      );
    },
    revoke: (id) =>
      call("revoke_share_link", { id }, (value) => value === true),
    resolve: (token) =>
      call("resolve_share_link", { token }, (value) => {
        if (value === null || value === undefined) return null;
        const row = recordOf(value, "resolve_share_link");
        const versionId = optionalText(row["versionId"]);
        return {
          id: textOf(row["id"]),
          subjectType: textOf(row["subjectType"]),
          subjectId: textOf(row["subjectId"]),
          role: textOf(row["role"]),
          ...(versionId === undefined ? {} : { versionId }),
        };
      }),
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
