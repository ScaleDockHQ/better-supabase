import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.service-principals.options`. */
export type ServicePrincipalsSqlOptions = { readonly extraColumns?: unknown };

export const servicePrincipalsSqlOptions: BlockOptionsSchema<ServicePrincipalsSqlOptions> =
  blockOptions<ServicePrincipalsSqlOptions>({ extraColumns: option.unknown() });
