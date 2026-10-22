import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks["service-accounts"].options`. */
export type ServiceAccountsSqlOptions = { readonly extraColumns?: unknown };

export const serviceAccountsSqlOptions: BlockOptionsSchema<ServiceAccountsSqlOptions> =
  blockOptions<ServiceAccountsSqlOptions>({ extraColumns: option.unknown() });
