import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.audit.options.ipHeader`. */
export interface AuditIpHeader {
  /** The request header that carries the client address. */
  readonly name: string;
  /** Which hop of a comma-separated list to take. Defaults to `"last"`. */
  readonly hop?: "first" | "last";
}

/** One entry of `blocks.audit.options.subjectColumns`. */
export interface AuditSubjectColumn {
  readonly type: "text" | "uuid" | "bigint";
  /**
   * The key in the row (or the event metadata) to read. Defaults to the column
   * name.
   */
  readonly from?: string;
}

/** `blocks.audit.options`. */
export type AuditSqlOptions = {
  readonly appendOnly?: boolean;
  readonly chain?: boolean;
  readonly correlationIdHeader?: string;
  readonly eventCategory?: string;
  readonly eventRoles?: readonly string[];
  readonly trustedRoles?: readonly string[];
  readonly eventSource?: string;
  readonly exempt?: unknown;
  readonly impersonators?: string;
  /**
   * The header `request_ip()` reads; defaults to the last `x-forwarded-for`
   * hop.
   */
  readonly ipHeader?: string | AuditIpHeader;
  readonly keepMappedMetadata?: boolean;
  readonly metadataColumns?: unknown;
  readonly partitioned?: boolean;
  readonly readPolicy?: boolean;
  readonly requestIdHeader?: string;
  readonly restricted?: boolean;
  /** A dotted JWT claim path; a caller that carries it is recorded as `staff`. */
  readonly staffClaim?: string;
  /** Indexed columns generated from a key of the row or event metadata. */
  readonly subjectColumns?: Readonly<Record<string, AuditSubjectColumn>>;
  readonly tenantColumn?: string;
  readonly tenantLabel?: unknown;
  readonly tenantLabelKey?: string;
  readonly values?: unknown;
};

export const auditSqlOptions: BlockOptionsSchema<AuditSqlOptions> =
  blockOptions<AuditSqlOptions>({
    appendOnly: option.boolean(),
    chain: option.boolean({ default: false }),
    correlationIdHeader: option.string({ default: "x-correlation-id" }),
    eventCategory: option.string({ default: "system" }),
    eventRoles: option.strings({ default: ["service_role"] }),
    trustedRoles: option.strings({ default: [] }),
    eventSource: option.string({ default: "app" }),
    exempt: option.unknown(),
    impersonators: option.string({ default: "show" }),
    ipHeader: option.unknown(),
    keepMappedMetadata: option.boolean({ default: false }),
    metadataColumns: option.unknown(),
    partitioned: option.boolean({ default: false }),
    readPolicy: option.boolean({ default: false }),
    requestIdHeader: option.string({ default: "x-request-id" }),
    restricted: option.boolean({ default: false }),
    staffClaim: option.string(),
    subjectColumns: option.unknown(),
    tenantColumn: option.string(),
    tenantLabel: option.unknown(),
    tenantLabelKey: option.string({ default: "id" }),
    values: option.unknown(),
  });
