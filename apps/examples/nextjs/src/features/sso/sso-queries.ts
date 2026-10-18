import { tenantOf } from "better-supabase/next";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

export interface SsoDomainRow {
  readonly id: string;
  readonly domain: string;
  readonly verified: boolean;
  readonly autoJoinRole: "member" | "admin" | null;
  readonly enforceSso: boolean;
  readonly recordName: string;
  readonly recordValue: string;
}

export interface SsoConnectionRow {
  readonly id: string;
  readonly metadataUrl: string | null;
  readonly domains: readonly string[];
  readonly createdAt: string;
}

export interface SsoSettingsData {
  readonly domains: readonly SsoDomainRow[];
  readonly connections: readonly SsoConnectionRow[];
}

function roleOf(value: string | undefined): "member" | "admin" | null {
  return value === "member" || value === "admin" ? value : null;
}

/**
 * The active organization's domains and SAML connections as the caller.
 * A failed read throws, so it is never cached and Retry reads again.
 */
export async function loadSsoSettings(): Promise<SsoSettingsData | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { sso } = blocks(supabase);

  const [domains, providers] = await Promise.all([
    sso.domains(tenant).orThrow(),
    sso.providers(tenant).orThrow(),
  ]);

  return {
    connections: providers.map((provider) => ({
      createdAt: provider.createdAt.toString(),
      domains: provider.domains,
      id: provider.id,
      metadataUrl: provider.metadataUrl ?? null,
    })),
    domains: domains.map((domain) => ({
      autoJoinRole: roleOf(domain.autoJoinRole),
      domain: domain.domain,
      enforceSso: domain.enforceSso,
      id: domain.id,
      recordName: domain.record.name,
      recordValue: domain.record.value,
      verified: domain.verifiedAt !== undefined,
    })),
  };
}
