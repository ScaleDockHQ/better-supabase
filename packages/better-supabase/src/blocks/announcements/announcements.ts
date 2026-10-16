import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import {
  allWithFields,
  type BlockFields,
  blockFields,
  extraOf,
  type FieldsOf,
  withFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  blockCall,
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
  toInstant,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";

export type AnnouncementSeverity = "info" | "success" | "warning" | "critical";

/**
 * Who sees it: everyone, members of some tenants, members with some roles,
 * or tenants on some plans (entitlement lookup keys, with the entitlements
 * module).
 */
export type AnnouncementAudience =
  | { readonly type: "all" }
  | { readonly type: "tenant"; readonly organizationIds: readonly string[] }
  | { readonly type: "role"; readonly roles: readonly string[] }
  | { readonly type: "plan"; readonly plans: readonly string[] };

export interface Announcement {
  readonly id: string;
  readonly title: string;
  readonly body: string;
  readonly severity: AnnouncementSeverity;
  readonly href: string | undefined;
  readonly startsAt: Temporal.Instant;
  readonly endsAt: Temporal.Instant | undefined;
  readonly dismissible: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** An announcement as staff see it, with its audience. */
export interface ManagedAnnouncement extends Announcement {
  readonly audience: AnnouncementAudience;
  readonly createdBy: string | undefined;
}

export interface AnnouncementInput {
  readonly title: string;
  /** Plain text or Markdown; the app renders it. */
  readonly body?: string;
  readonly severity?: AnnouncementSeverity;
  /** A link for "Learn more": `https://` or a path. */
  readonly href?: string | null;
  readonly audience?: AnnouncementAudience;
  readonly startsAt?: Temporal.Instant;
  readonly endsAt?: Temporal.Instant | null;
  readonly dismissible?: boolean;
}

export interface AnnouncementsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /**
   * A Standard Schema for the announcement columns the app adds
   * (`blocks.announcements.options.extraColumns`), keyed by column name. It
   * types and parses them on every read, and validates them on `publish`
   * and `update`, which return a `validation` error for a bad value.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Announcements<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly transport: BlockTransport;
  /** The module schema, or its API schema: `defineBlocks` passes it from `blocks.generated.ts`. Default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

/** `F` is the extra fields `options.fields` describes. */
export interface Announcements<F extends object = Record<never, never>> {
  /** The caller's live, undismissed announcements; pass the active tenant for tenant, role and plan audiences. */
  listActive(
    organizationId?: string | null,
  ): AsyncResult<readonly (Announcement & F)[]>;
  /** Hides one for the caller; `false` when it was hidden already. */
  dismiss(announcementId: string): AsyncResult<boolean>;
  /** Every announcement; needs `announcements.manage` on the platform. */
  list(): AsyncResult<readonly (ManagedAnnouncement & F)[]>;
  /** Keys besides the input's own are the announcement's extra columns. */
  publish(
    input: AnnouncementInput & Partial<F>,
  ): AsyncResult<ManagedAnnouncement & F>;
  update(
    announcementId: string,
    input: Partial<AnnouncementInput> & Partial<F>,
  ): AsyncResult<ManagedAnnouncement & F>;
  remove(announcementId: string): AsyncResult<boolean>;
}

const SEVERITIES: ReadonlySet<string> = new Set([
  "info",
  "success",
  "warning",
  "critical",
]);

function severityOf(value: unknown): AnnouncementSeverity {
  const text = textOf(value);
  // SAFETY: the set holds exactly the AnnouncementSeverity values.
  return SEVERITIES.has(text) ? (text as AnnouncementSeverity) : "info";
}

function announcementOf(value: unknown): Announcement {
  const row = recordOf(value, "announcements");
  return {
    id: textOf(row["id"]),
    title: textOf(row["title"]),
    body: textOf(row["body"] ?? ""),
    severity: severityOf(row["severity"]),
    href: optionalText(row["href"]),
    startsAt: toInstant(textOf(row["starts_at"])),
    endsAt: optionalInstant(row["ends_at"]),
    dismissible: row["dismissible"] !== false,
    createdAt: toInstant(textOf(row["created_at"])),
    updatedAt: toInstant(textOf(row["updated_at"])),
  };
}

function audienceOf(type: unknown, targets: unknown): AnnouncementAudience {
  const values = stringsOf(targets);
  switch (type) {
    case "tenant":
      return { type, organizationIds: values };
    case "role":
      return { type, roles: values };
    case "plan":
      return { type, plans: values };
    default:
      return { type: "all" };
  }
}

function managedOf(value: unknown): ManagedAnnouncement {
  const row = recordOf(value, "announcements");
  return {
    ...announcementOf(row),
    audience: audienceOf(row["audience"], row["targets"]),
    createdBy: optionalText(row["created_by"]),
  };
}

function audienceFields(audience: AnnouncementAudience): {
  readonly audience: string;
  readonly targets: readonly string[];
} {
  switch (audience.type) {
    case "all":
      return { audience: "all", targets: [] };
    case "tenant":
      return { audience: "tenant", targets: audience.organizationIds };
    case "role":
      return { audience: "role", targets: audience.roles };
    case "plan":
      return { audience: "plan", targets: audience.plans };
    default: {
      const unknown: never = audience;
      throw new TypeError(`Unknown audience ${JSON.stringify(unknown)}`);
    }
  }
}

/** The columns `save_announcement` sets, from the fields the input names. */
function fieldsOf(input: Partial<AnnouncementInput>): Record<string, unknown> {
  const fields: Record<string, unknown> = {};
  if (input.title !== undefined) fields["title"] = input.title;
  if (input.body !== undefined) fields["body"] = input.body;
  if (input.severity !== undefined) fields["severity"] = input.severity;
  if (input.href !== undefined) fields["href"] = input.href;
  if (input.audience !== undefined) {
    Object.assign(fields, audienceFields(input.audience));
  }
  if (input.startsAt !== undefined) {
    fields["starts_at"] = instantArg(input.startsAt);
  }
  if (input.endsAt !== undefined) {
    fields["ends_at"] = instantArg(input.endsAt);
  }
  if (input.dismissible !== undefined) {
    fields["dismissible"] = input.dismissible;
  }
  return fields;
}

const INPUT_KEYS: ReadonlySet<string> = new Set([
  "title",
  "body",
  "severity",
  "href",
  "audience",
  "startsAt",
  "endsAt",
  "dismissible",
]);

export function createAnnouncements<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: AnnouncementsOptions<S>): Announcements<FieldsOf<S>> {
  type F = FieldsOf<S>;
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(
    options.fields,
    "announcement fields",
  );
  const save = (
    id: string | null,
    input: Partial<AnnouncementInput>,
  ): AsyncResult<ManagedAnnouncement & F> => {
    // An unknown audience throws here, before the call, as it always has.
    const columns = fieldsOf(input);
    return AsyncResult.from(() => fields.write(extraOf(input, INPUT_KEYS)))
      .andThen((extra) =>
        call(
          "save_announcement",
          { id, fields: { ...extra, ...columns } },
          (value) => value,
        ),
      )
      .andThen((value) => withFields(fields, value, managedOf(value)));
  };
  const client: Announcements<F> = {
    listActive: (organizationId) =>
      call(
        "active_announcements",
        { tenant: organizationId ?? null },
        (value) =>
          recordsOf(value, "active_announcements").map(
            (raw) => [raw, announcementOf(raw)] as const,
          ),
      ).andThen((rows) => allWithFields(fields, rows)),
    dismiss: (announcementId) =>
      call(
        "dismiss_announcement",
        { id: announcementId },
        (value) => value === true,
      ),
    list: () =>
      call("list_announcements", {}, (value) =>
        recordsOf(value, "list_announcements").map(
          (raw) => [raw, managedOf(raw)] as const,
        ),
      ).andThen((rows) => allWithFields(fields, rows)),
    publish: (input) => save(null, input),
    update: (announcementId, input) => save(announcementId, input),
    remove: (announcementId) =>
      call(
        "delete_announcement",
        { id: announcementId },
        (value) => value === true,
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "announcements",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
