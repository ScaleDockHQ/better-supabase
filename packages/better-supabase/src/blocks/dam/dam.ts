import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult as AsyncResultType } from "../../core/result.ts";
import type { AttachmentStorage } from "../attachments/attachments.ts";
import type { PreviewRenderer } from "../drive/preview.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  DAM_RENDITION_STATUSES,
  DAM_USAGE_RIGHT_STATUSES,
} from "../../sql/modules/dam-values.ts";
import { stored } from "../attachments/attachments.ts";
import { previewRendererOf } from "../drive/preview.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** A rendition name such as `thumbnail` or `web`. */
export type DamRenditionKind = string;

/** Where a rendition is in its life. */
export type DamRenditionStatus = (typeof DAM_RENDITION_STATUSES)[number];

/** Whether a usage right lets the file be used today. */
export type DamUsageRightStatus = (typeof DAM_USAGE_RIGHT_STATUSES)[number];

/** One derived version of a drive file. */
export interface DamRendition {
  readonly id: string;
  readonly organizationId: string;
  readonly nodeId: string;
  readonly kind: DamRenditionKind;
  readonly status: DamRenditionStatus;
  readonly format?: string;
  readonly width?: number;
  readonly height?: number;
  readonly sizeBytes?: number;
  /** The storage path of the rendition. */
  readonly path?: string;
  readonly error?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface DamRenditionInput {
  /** Default `ready`. */
  readonly status?: DamRenditionStatus;
  readonly format?: string;
  readonly width?: number;
  readonly height?: number;
  readonly sizeBytes?: number;
  readonly path?: string;
  readonly error?: string;
}

/** The right to use a file. */
export interface DamUsageRight {
  readonly id: string;
  readonly organizationId: string;
  readonly nodeId: string;
  readonly licensee: string;
  /** Absent for every territory. */
  readonly territory?: string;
  /** Absent for every channel. */
  readonly channel?: string;
  readonly startsOn: Temporal.PlainDate;
  /** The last day of the right. Absent when it never expires. */
  readonly expiresOn?: Temporal.PlainDate;
  readonly status: DamUsageRightStatus;
  readonly note?: string;
  readonly revokedAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
}

export interface DamUsageRightInput {
  readonly nodeId: string;
  readonly licensee: string;
  readonly territory?: string | null;
  readonly channel?: string | null;
  /** Default today. */
  readonly startsOn?: Temporal.PlainDate;
  /** On or after `startsOn`. */
  readonly expiresOn?: Temporal.PlainDate | null;
  readonly note?: string | null;
}

export interface DamUsageRightListOptions {
  readonly nodeId?: string;
  readonly status?: DamUsageRightStatus;
  /** Only unrevoked rights that end within this many days. */
  readonly expiringWithinDays?: number;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

/** The answer of {@link Dam.checkUsage}. */
export interface DamUsageCheck {
  readonly allowed: boolean;
  /** The right that allows it, the one that lasts longest. */
  readonly rightId?: string;
  readonly expiresOn?: Temporal.PlainDate;
}

/** What {@link Dam.renderRenditions} renders. */
export interface DamRenderInput {
  readonly nodeId: string;
  /** The file's name, for the renderer. */
  readonly name: string;
  readonly mimeType: string;
  readonly file: Blob;
  /** Render only these kinds. Default every configured kind. */
  readonly kinds?: readonly DamRenditionKind[];
  readonly signal?: AbortSignal;
}

export interface Dam {
  /**
   * Records a rendition of a file, replacing the one of that kind; needs
   * `dam.write`.
   */
  recordRendition(input: {
    nodeId: string;
    kind: DamRenditionKind;
    input?: DamRenditionInput | undefined;
  }): AsyncResultType<DamRendition>;
  listRenditions(nodeId: string): AsyncResultType<readonly DamRendition[]>;
  /**
   * Renders the configured kinds through their drive preview renderers, stores
   * each page-one image and records the rendition. A kind the renderer skips is
   * left out; one that throws is recorded as `failed` and the rest go on. Needs
   * the `renditions` and `storage` options.
   */
  renderRenditions(
    input: DamRenderInput,
  ): AsyncResultType<readonly DamRendition[]>;
  /** Grants a usage right; needs `dam.write`. */
  grantRight(input: DamUsageRightInput): AsyncResultType<DamUsageRight>;
  /** Revokes a right. It stays in the history; needs `dam.write`. */
  revokeRight(rightId: string): AsyncResultType<DamUsageRight>;
  listRights(
    options?: DamUsageRightListOptions,
  ): AsyncResultType<readonly DamUsageRight[]>;
  /**
   * Whether the file may be used on a day (default today) in a territory and
   * channel. A file without any right is not allowed.
   */
  checkUsage(
    input: { nodeId: string } & {
      readonly on?: Temporal.PlainDate;
      readonly territory?: string;
      readonly channel?: string;
    },
  ): AsyncResultType<DamUsageCheck>;
  /**
   * Notifies the member who granted each right that ends within `days` days
   * (default 30), once per expiry date. Run it daily; needs a service-role
   * transport. Returns how many rights it reported.
   */
  notifyExpiring(days?: number): AsyncResultType<number>;
}

/** A rendition kind and the renderer that makes it. */
export interface DamRenditionSpec {
  readonly renderer: PreviewRenderer;
  /** The page to keep, from 1. Default 1. */
  readonly page?: number;
}

/** Options for {@link createDam}. */
export interface DamOptions extends BlockOptions {
  /**
   * A service-role `supabase.storage` that uploads. Needed by
   * `renderRenditions`.
   */
  readonly storage?: AttachmentStorage;
  /** The bucket for renditions. Default `dam`. */
  readonly bucket?: string;
  /** The kinds `renderRenditions` makes, such as `{ thumbnail: { renderer } }`. */
  readonly renditions?: Readonly<Record<DamRenditionKind, DamRenditionSpec>>;
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Dam>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().PlainDate.from(value)
    : undefined;

const dateArg = (
  value: Temporal.PlainDate | null | undefined,
): string | null | undefined =>
  value === undefined ? undefined : value === null ? null : value.toString();

function renditionOf(value: unknown, fn: string): DamRendition {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    nodeId: textOf(row["nodeId"]),
    kind: textOf(row["kind"]),
    status: enumOrThrow(
      row["status"],
      DAM_RENDITION_STATUSES,
      "rendition status",
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("format", optionalText(row["format"])),
    ...optional("width", numberOf(row["width"])),
    ...optional("height", numberOf(row["height"])),
    ...optional("sizeBytes", numberOf(row["sizeBytes"])),
    ...optional("path", optionalText(row["path"])),
    ...optional("error", optionalText(row["error"])),
  };
}

function rightOf(value: unknown, fn: string): DamUsageRight {
  const row = recordOf(value, fn);
  const startsOn = optionalDate(row["startsOn"]);

  if (startsOn === undefined) {
    throw new TypeError(`${fn}: startsOn is missing`);
  }

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    nodeId: textOf(row["nodeId"]),
    licensee: textOf(row["licensee"]),
    startsOn,
    status: enumOrThrow(
      row["status"],
      DAM_USAGE_RIGHT_STATUSES,
      "usage right status",
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("territory", optionalText(row["territory"])),
    ...optional("channel", optionalText(row["channel"])),
    ...optional("expiresOn", optionalDate(row["expiresOn"])),
    ...optional("note", optionalText(row["note"])),
    ...optional(
      "revokedAt",
      typeof row["revokedAt"] === "string"
        ? requiredInstant(row["revokedAt"], "revokedAt")
        : undefined,
    ),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

/**
 * Digital asset management on the drive: renditions of a file made through the
 * drive's preview renderers, and the usage rights that say who may use it,
 * where and until when.
 */
export function createDam(options: DamOptions): Dam {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);
  const bucket = options.bucket ?? "dam";

  const specs = Object.entries(options.renditions ?? {}).map(
    ([kind, spec]) =>
      [kind, { ...spec, renderer: previewRendererOf(spec.renderer) }] as const,
  );

  const record = (
    organizationId: string,
    nodeId: string,
    kind: DamRenditionKind,
    input: DamRenditionInput,
  ): AsyncResultType<DamRendition> =>
    call(
      "record_rendition",
      {
        tenant: organizationId,
        node_id: nodeId,
        kind,
        input: definedOf(input),
      },
      (value) => renditionOf(value, "record_rendition"),
    );

  const client: Dam = {
    recordRendition: ({ nodeId, kind, input = {} }) =>
      tenant().andThen((organizationId) =>
        record(organizationId, nodeId, kind, input),
      ),
    listRenditions: (nodeId) =>
      tenant().andThen((organizationId) =>
        call(
          "list_renditions",
          { tenant: organizationId, node_id: nodeId },
          (value) =>
            recordsOf(value, "list_renditions").map((row) =>
              renditionOf(row, "list_renditions"),
            ),
        ),
      ),
    renderRenditions: (input) => {
      const upload = options.storage?.from(bucket);
      const put = upload?.upload?.bind(upload);

      if (put === undefined || specs.length === 0) {
        return AsyncResult.err(
          dbError(
            "invalid_request",
            "createDam needs a storage client that uploads and at least one rendition to render",
            { hint: "DAM_RENDER_CONFIG" },
          ),
        );
      }

      return tenant().andThen((organizationId) =>
        AsyncResult.from(async () => {
          const made: DamRendition[] = [];

          const wanted =
            input.kinds === undefined ? undefined : new Set(input.kinds);

          for (const [kind, spec] of specs) {
            if (wanted !== undefined && !wanted.has(kind)) {
              continue;
            }

            const page = spec.page ?? 1;
            let pages;

            try {
              pages = await spec.renderer.render(input.file, {
                name: input.name,
                mimeType: input.mimeType,
                maxPages: page,
                ...(input.signal === undefined ? {} : { signal: input.signal }),
              });
            } catch (error) {
              const failed = await record(organizationId, input.nodeId, kind, {
                status: "failed",
                error: (error instanceof Error
                  ? error.message
                  : String(error)
                ).slice(0, 500),
              });

              if (!failed.ok) {
                return failed;
              }

              made.push(failed.data);
              continue;
            }

            const body = pages?.[page - 1];

            if (body === undefined) {
              continue;
            }

            const path = `${organizationId}/${input.nodeId}/${kind}`;

            const uploaded = await stored(
              put(path, body.body, {
                contentType: body.contentType,
                upsert: true,
              }),
            );

            if (!uploaded.ok) {
              return uploaded;
            }

            const recorded = await record(organizationId, input.nodeId, kind, {
              status: "ready",
              format: body.contentType.split("/")[1] ?? body.contentType,
              sizeBytes: body.body.size,
              path,
            });

            if (!recorded.ok) {
              return recorded;
            }

            made.push(recorded.data);
          }

          return ok(made);
        }),
      );
    },
    grantRight: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "grant_usage_right",
          {
            tenant: organizationId,
            input: definedOf({
              ...input,
              startsOn: dateArg(input.startsOn),
              expiresOn: dateArg(input.expiresOn),
            }),
          },
          (value) => rightOf(value, "grant_usage_right"),
        ),
      ),
    revokeRight: (rightId) =>
      call("revoke_usage_right", { right_id: rightId }, (value) =>
        rightOf(value, "revoke_usage_right"),
      ),
    listRights: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_usage_rights",
          { tenant: organizationId, filters: definedOf(list) },
          (value) =>
            recordsOf(value, "list_usage_rights").map((row) =>
              rightOf(row, "list_usage_rights"),
            ),
        ),
      ),
    checkUsage: ({ nodeId, ...check }) =>
      tenant().andThen((organizationId) =>
        call(
          "check_usage",
          {
            tenant: organizationId,
            node_id: nodeId,
            filters: definedOf({
              on: dateArg(check.on),
              territory: check.territory,
              channel: check.channel,
            }),
          },
          (value) => {
            const row = recordOf(value, "check_usage");

            return {
              allowed: row["allowed"] === true,
              ...optional("rightId", optionalText(row["rightId"])),
              ...optional("expiresOn", optionalDate(row["expiresOn"])),
            };
          },
        ),
      ),
    notifyExpiring: (days = 30) =>
      call("notify_expiring_usage_rights", { days }, (value) =>
        typeof value === "number" ? value : 0,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "dam",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
