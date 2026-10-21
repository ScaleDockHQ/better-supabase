import type { VercelMarketplace } from "better-supabase/blocks/vercel-marketplace";
import type { BetterPostgres } from "better-supabase/postgres";

import { DbException, dbError } from "better-supabase";
import { createApiKeys } from "better-supabase/blocks/api-keys";
import { createOAuthServer } from "better-supabase/blocks/oauth-server";
import { createSigningKeys } from "better-supabase/blocks/signing-keys";
import {
  createVercelMarketplace,
  sqlTransport,
} from "better-supabase/blocks/vercel-marketplace";
import { createPostgres } from "better-supabase/postgres";

interface Blocks {
  readonly postgres: BetterPostgres;
  readonly apiKeys: ReturnType<typeof createApiKeys>;
  readonly oauth: ReturnType<typeof createOAuthServer>;
  readonly signingKeys: ReturnType<typeof createSigningKeys>;
}

let blocks: Blocks | undefined;
let marketplace: VercelMarketplace | undefined;

/**
 * The service-role block clients, over the direct connection in
 * `$SUPABASE_DB_URL`: the block tables live outside the Data API.
 */
export function serviceBlocks(): Blocks {
  if (!blocks) {
    const postgres = createPostgres({ max: 3 });
    const transport = sqlTransport(postgres.admin);

    blocks = {
      postgres,
      apiKeys: createApiKeys({ transport }),
      oauth: createOAuthServer({ transport }),
      signingKeys: createSigningKeys({ transport }),
    };
  }

  return blocks;
}

/**
 * The Marketplace client. Without the integration's credentials it throws a
 * `DbException`, which `onError` answers as Problem Details.
 */
export function vercelMarketplace(): VercelMarketplace {
  const clientId = process.env["VERCEL_MARKETPLACE_CLIENT_ID"];
  const clientSecret = process.env["VERCEL_MARKETPLACE_CLIENT_SECRET"];

  if (!clientId || !clientSecret) {
    throw new DbException(
      dbError(
        "network",
        "Set VERCEL_MARKETPLACE_CLIENT_ID and VERCEL_MARKETPLACE_CLIENT_SECRET",
      ),
    );
  }

  marketplace ??= createVercelMarketplace({
    transport: sqlTransport(serviceBlocks().postgres.admin),
    clientId,
    clientSecret,
  });

  return marketplace;
}
