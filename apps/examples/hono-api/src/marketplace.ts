import type {
  MarketplaceResourceHooks,
  MarketplaceSecret,
  PartnerApiOptions,
} from "better-supabase/blocks/vercel-marketplace";

import { serviceBlocks, vercelMarketplace } from "./blocks";

type PartnerApi = (request: Request) => Promise<Response>;

let handler: PartnerApi | undefined;

async function issueKey(tenant: string): Promise<MarketplaceSecret> {
  const { key, token } = await serviceBlocks()
    .apiKeys.create({
      name: "Vercel Marketplace",
      organizationId: tenant,
      scopes: ["*"],
    })
    .orThrow();

  return { name: "APP_API_KEY", value: token, ref: key.id };
}

const resources: MarketplaceResourceHooks = {
  async provision({ resource }) {
    const slug = `vercel-${resource.id}`.toLowerCase();

    const [organization] = await serviceBlocks().postgres.admin.queryRaw<{
      id: string;
    }>(
      "insert into public.organizations (name, slug) values ($1, $2) returning id",
      [resource.name, slug],
    );

    if (!organization) {
      throw new Error(`No organization was created for ${resource.id}`);
    }

    return {
      tenant: organization.id,
      tenantCreated: true,
      secrets: [await issueKey(organization.id)],
    };
  },
  async rotate({ resource }) {
    if (!resource.tenant) {
      throw new Error(`Resource ${resource.externalId} has no tenant`);
    }

    return { secrets: [await issueKey(resource.tenant)] };
  },
  async revoke({ previous }) {
    for (const id of previous) {
      await serviceBlocks().apiKeys.revoke(id).orThrow();
    }
  },
};

const options: PartnerApiOptions = {
  plans: [
    {
      id: "free",
      name: "Free",
      type: "subscription",
      scope: "resource",
      paymentMethodRequired: false,
      billing: { items: [] },
    },
  ],
  resources,
  async removeTenant({ tenant, created }) {
    if (created) {
      await serviceBlocks().postgres.admin.queryRaw(
        "delete from public.organizations where id = $1",
        [tenant],
      );
    }
  },
};

/** The Partner API Vercel calls, built on the first request. */
export function partnerApi(request: Request): Promise<Response> {
  handler ??= vercelMarketplace().partnerApi(options);

  return handler(request);
}
