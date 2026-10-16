import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

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
  readonly keepMappedMetadata?: boolean;
  readonly metadataColumns?: unknown;
  readonly partitioned?: boolean;
  readonly readPolicy?: boolean;
  readonly requestIdHeader?: string;
  readonly restricted?: boolean;
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
    keepMappedMetadata: option.boolean({ default: false }),
    metadataColumns: option.unknown(),
    partitioned: option.boolean({ default: false }),
    readPolicy: option.boolean({ default: false }),
    requestIdHeader: option.string({ default: "x-request-id" }),
    restricted: option.boolean({ default: false }),
    tenantColumn: option.string(),
    tenantLabel: option.unknown(),
    tenantLabelKey: option.string({ default: "id" }),
    values: option.unknown(),
  });
