import type { OAuthGrant, SupabaseClient } from "@supabase/supabase-js";

import { AuthApiError } from "@supabase/supabase-js";

import { isRecord } from "../core/guards.ts";

/**
 * `client` with `auth.oauth.listGrants` and `revokeGrant` sent with the
 * request's access token. A context client holds the caller's bearer but no
 * Auth session, so supabase-js answers both with `AuthSessionMissingError`.
 */
export function withBearerGrants(
  client: SupabaseClient,
  options: {
    readonly url: string;
    readonly apiKey: string;
    readonly token: string;
    readonly fetch?: typeof globalThis.fetch | undefined;
  },
): SupabaseClient {
  const oauth = client.auth.oauth;

  const grants = new URL(
    "auth/v1/user/oauth/grants",
    options.url.endsWith("/") ? options.url : `${options.url}/`,
  );

  const send = (
    method: "GET" | "DELETE",
    clientId?: string,
  ): Promise<Response> => {
    const target = new URL(grants);

    if (clientId !== undefined) {
      target.searchParams.set("client_id", clientId);
    }

    return (options.fetch ?? globalThis.fetch)(target, {
      method,
      headers: {
        apikey: options.apiKey,
        authorization: `Bearer ${options.token}`,
      },
    });
  };

  const failure = async (response: Response): Promise<AuthApiError> => {
    const body: unknown = await response.json().catch(() => undefined);

    const field = (key: string): string | undefined => {
      const value = isRecord(body) ? body[key] : undefined;

      return typeof value === "string" ? value : undefined;
    };

    return new AuthApiError(
      field("msg") ??
        field("message") ??
        field("error_description") ??
        response.statusText,
      response.status,
      field("error_code") ?? field("code"),
    );
  };

  const listGrants: typeof oauth.listGrants = async () => {
    const response = await send("GET");

    if (!response.ok) {
      return { data: null, error: await failure(response) };
    }

    const data: unknown = await response.json();

    // SAFETY: Supabase Auth answers GET /user/oauth/grants with the grant list.
    return { data: data as OAuthGrant[], error: null };
  };

  const revokeGrant: typeof oauth.revokeGrant = async ({ clientId }) => {
    const response = await send("DELETE", clientId);

    if (!response.ok) {
      return { data: null, error: await failure(response) };
    }

    return { data: {}, error: null };
  };

  Object.assign(oauth, { listGrants, revokeGrant });

  return client;
}
