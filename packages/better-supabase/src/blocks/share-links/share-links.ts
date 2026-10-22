import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { subjectRefOf } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  applyTemporal,
  blockCall,
  instantArg,
  isRecord,
  nullableInstant,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

export interface ShareLinksOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the link's extra columns
   * (`blocks.share-links.options.extraColumns`), keyed by database name. It
   * types and parses them on `create` and `list`, and validates them on
   * `create`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<ShareLinks<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export interface CreatedShareLink<F extends object = Record<never, never>> {
  readonly id: string;
  /** Returned once. Later calls only see the hash. */
  readonly token: string;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

/** A link `list` returns. The token is never returned again. */
export interface ShareLink<F extends object = Record<never, never>> {
  readonly id: string;
  readonly role: string;
  readonly expiresAt: Temporal.Instant | null;
  readonly revokedAt: Temporal.Instant | null;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface CreateShareLinkOptions<
  F extends object = Record<never, never>,
> {
  /** The link's extra columns. */
  readonly fields?: Partial<F>;
  /** `view` unless set. */
  readonly role?: string;
  /**
   * Pins the link to one of the subject's versions (the versions module), which
   * `versions.getShared(token)` reads for anon.
   */
  readonly versionId?: string;
  /**
   * When the link stops resolving. It must be in the future
   * (`SHARE_EXPIRY_INVALID`); without it the link lives until revoked.
   */
  readonly expiresAt?: Temporal.Instant;
  /**
   * How many times `resolve` may open the link. Without it the link opens until
   * it is revoked or expires.
   */
  readonly maxUses?: number;
}

/** What a live token points at. */
export interface ResolvedShareLink {
  readonly id: string;
  /** The organization the link was created in. */
  readonly organizationId: string;
  readonly subject: RecordRef;
  readonly role: string;
  /** The version the link is pinned to, when it has one. */
  readonly versionId?: string;
  /** When the link stops resolving, when it has an expiry. */
  readonly expiresAt?: Temporal.Instant;
  /** How many times the link may be opened, when it has a limit. */
  readonly maxUses?: number;
}

/**
 * `F` is the extra fields `options.fields` describes. `create` and `recordView`
 * act in the block's `tenant`.
 */
export interface ShareLinks<F extends object = Record<never, never>> {
  /** A link to `subject`. A role string is the same as `{ role }`. */
  create(
    subject: RecordRef,
    options?: string | CreateShareLinkOptions<F>,
  ): AsyncResult<CreatedShareLink<F>>;
  /** The link's creator, or a member with `share_links.create`. */
  revoke(id: string): AsyncResult<boolean>;
  /**
   * `null` for an unknown, revoked, expired or used-up token. Each call counts
   * one use.
   */
  resolve(token: string): AsyncResult<ResolvedShareLink | null>;
  /** A member of the tenant records a view of `subject`. */
  recordView(
    subject: RecordRef,
    viewerKind: string,
    viewer?: string,
  ): AsyncResult<boolean>;
  /**
   * The links to `subject` the caller created or may read (`share_links.read`),
   * revoked ones included.
   */
  list(subject: RecordRef): AsyncResult<readonly ShareLink<F>[]>;
  /** Stars or unstars `subject` for the caller. */
  setState(subject: RecordRef, starred: boolean): AsyncResult<boolean>;
}

const fieldsOf = (row: Readonly<Record<string, unknown>>) =>
  isRecord(row["fields"]) ? row["fields"] : {};

/** The `share-links` SQL module as typed calls. */
export function createShareLinks<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ShareLinksOptions<S>): ShareLinks<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "share link fields",
  );

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: ShareLinks<F> = {
    create: (subject, link = {}) => {
      const {
        role,
        versionId,
        expiresAt,
        maxUses,
        fields: extra,
      }: CreateShareLinkOptions<F> = typeof link === "string"
        ? { role: link }
        : link;

      return tenant().andThen((organizationId) =>
        fields.args(extra).andThen((checked) =>
          call(
            "create_share_link",
            {
              tenant: organizationId,
              subject_type: subject.type,
              subject_id: subject.id,
              role: role ?? "view",
              version_id: versionId ?? null,
              expires_at: instantArg(expiresAt) ?? null,
              max_uses: maxUses ?? null,
              fields: checked,
            },
            (value) => {
              const row = recordOf(value, "create_share_link");

              return {
                id: textOf(row["id"]),
                token: textOf(row["token"]),
                fields: fieldsOf(row),
              };
            },
          ).andThen(fields.row),
        ),
      );
    },
    revoke: (id) =>
      call("revoke_share_link", { id }, (value) => value === true),
    resolve: (token) =>
      call("resolve_share_link", { token }, (value) => {
        if (value === null || value === undefined) {
          return null;
        }

        const row = recordOf(value, "resolve_share_link");
        const versionId = optionalText(row["versionId"]);
        const expiresAt = optionalInstant(row["expiresAt"]);

        const maxUses =
          typeof row["maxUses"] === "number" ? row["maxUses"] : undefined;

        return {
          id: textOf(row["id"]),
          organizationId: textOf(row["organizationId"]),
          subject: subjectRefOf(row["subjectType"], row["subjectId"]),
          role: textOf(row["role"]),
          ...(versionId === undefined ? {} : { versionId }),
          ...(expiresAt === undefined ? {} : { expiresAt }),
          ...(maxUses === undefined ? {} : { maxUses }),
        };
      }),
    recordView: (subject, viewerKind, viewer) =>
      tenant().andThen((organizationId) =>
        call(
          "record_view",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            viewer_kind: viewerKind,
            viewer: viewer ?? null,
          },
          (value) => value === true,
        ),
      ),
    list: (subject) =>
      call(
        "list_share_links",
        { subject_type: subject.type, subject_id: subject.id },
        (value) =>
          recordsOf(value, "list_share_links").map((row) => ({
            id: textOf(row["id"]),
            role: textOf(row["role"]),
            expiresAt: nullableInstant(row["expiresAt"]),
            revokedAt: nullableInstant(row["revokedAt"]),
            fields: fieldsOf(row),
          })),
      ).andThen(fields.rows),
    setState: (subject, starred) =>
      call(
        "set_user_state",
        { subject_type: subject.type, subject_id: subject.id, starred },
        (value) => value === true,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "share-links",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
