import "server-only";
import type { CredentialProvider } from "better-supabase/credentials";
import type { VercelConnectRef } from "better-supabase/vercel-connect";

import { vercelConnectCredentials } from "better-supabase/vercel-connect";

import { env } from "@/env";

export type IntegrationId = "gmail" | "outlook";

export interface Integration {
  readonly id: IntegrationId;
  readonly name: string;
  readonly ref: VercelConnectRef;
}

/** The connector UID each integration needs; unset ones stay hidden. */
const CONNECTORS = {
  gmail: { name: "Gmail", uid: env.CONNECT_GMAIL_CONNECTOR },
  outlook: { name: "Outlook", uid: env.CONNECT_OUTLOOK_CONNECTOR },
} satisfies Record<IntegrationId, { name: string; uid: string | undefined }>;

/** The integrations this deployment has a Vercel Connect connector for. */
export function integrations(): readonly Integration[] {
  return Object.entries(CONNECTORS).flatMap(([id, { name, uid }]) =>
    uid === undefined || !isIntegrationId(id)
      ? []
      : [{ id, name, ref: { provider: "vercel-connect", connector: uid } }],
  );
}

function isIntegrationId(value: string): value is IntegrationId {
  return value === "gmail" || value === "outlook";
}

export function integrationOf(id: string): Integration | undefined {
  return integrations().find((integration) => integration.id === id);
}

let provider: CredentialProvider | undefined;

/**
 * One provider per server instance, so `@vercel/connect`'s token cache is
 * shared. On Vercel it signs in with the deployment's OIDC token; locally,
 * `vercel env pull` writes `VERCEL_OIDC_TOKEN`.
 */
export function connectCredentials(): CredentialProvider {
  provider ??= vercelConnectCredentials();

  return provider;
}
