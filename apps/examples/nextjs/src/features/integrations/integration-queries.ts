import "server-only";
import type { DbError } from "better-supabase";

import { getSession } from "@/features/user/user-queries";

import type { IntegrationId } from "./integrations-server";

import { connectCredentials, integrations } from "./integrations-server";

/**
 * `connected`: Connect has a token for the user. `available`: Connect needs the
 * user's consent, which it reports the same way whether they never connected or
 * the grant was revoked or expired.
 */
export type IntegrationStatus = "connected" | "available";

export interface IntegrationRow {
  readonly id: IntegrationId;
  readonly name: string;
  readonly status: IntegrationStatus;
}

/** A read that failed renders its error in the card, with a Retry. */
export type IntegrationsRead =
  | { readonly ok: true; readonly rows: readonly IntegrationRow[] }
  | { readonly ok: false; readonly error: DbError };

const needsConsent = (error: DbError): boolean =>
  error.hint === "CREDENTIAL_NOT_FOUND" ||
  error.hint === "CREDENTIAL_AUTHORIZATION_REQUIRED";

/**
 * Asks Connect for each integration's token as the signed-in user. Connect
 * caches tokens in process, so a page view costs a round trip only when one is
 * missing or about to expire.
 */
export async function getIntegrations(): Promise<IntegrationsRead> {
  const session = await getSession();

  if (session.kind !== "user") {
    return { ok: true, rows: [] };
  }

  const subject = { type: "user", id: session.user.id } as const;
  const credentials = connectCredentials();

  const reads = await Promise.all(
    integrations().map(async (integration) => ({
      integration,
      token: await credentials.getToken(integration.ref, { subject }),
    })),
  );

  const rows: IntegrationRow[] = [];

  for (const { integration, token } of reads) {
    if (!token.ok && !needsConsent(token.error)) {
      return { ok: false, error: token.error };
    }

    rows.push({
      id: integration.id,
      name: integration.name,
      status: token.ok ? "connected" : "available",
    });
  }

  return { ok: true, rows };
}
