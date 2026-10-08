import type { AuthState } from "../../src/auth/resolve.ts";
import type { BetterSupabase } from "../../src/core/define.ts";
import type { BetterServer } from "../../src/server/server.ts";
import type { TestSigner } from "../../src/testing/jwt.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { createServer } from "../../src/server/server.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import {
  type Database,
  type Functions,
  type Models,
  schema,
} from "./generated-camel.ts";

const PROJECT_URL: string = "https://abcdefghijklmnopqrst.supabase.co";
export const USER: string = "11111111-1111-4111-8111-111111111111";
export const env: { url: string; publishableKey: string; jwksUrl: URL } = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
export const signer: TestSigner = await createTestSigner();
export const betterSupabase: BetterSupabase<Models, Database, Functions> =
  defineSupabase(schema);
export const server: BetterServer<Models, Functions, unknown> = createServer(
  betterSupabase,
  {
    env,
    auth: { jwks: signer.jwks as never },
    prefetchJwks: false,
  },
);

/** A request as a signed-in user with `app_metadata`, or anonymous without one. */
export async function requestAs(
  appMetadata?: Record<string, unknown>,
  init: RequestInit & { readonly url?: string } = {},
): Promise<Request> {
  const headers = new Headers(init.headers);
  if (appMetadata) {
    headers.set(
      "authorization",
      `Bearer ${await signer.sign({ sub: USER, app_metadata: appMetadata })}`,
    );
  }
  return new Request(init.url ?? "https://app.test/page", { ...init, headers });
}

/** The auth state for `requestAs(appMetadata)`. */
export async function authAs(
  appMetadata?: Record<string, unknown>,
): Promise<AuthState> {
  return (await server.context(await requestAs(appMetadata))).auth;
}
