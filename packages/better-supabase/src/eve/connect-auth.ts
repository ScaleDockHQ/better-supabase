import type { CredentialSubject } from "../credentials/provider.ts";
import type { EveConnectionPrincipal } from "./connections.ts";

import { connectSubject } from "../vercel-connect/vercel-connect.ts";

/** What `connectAuth` hands to `connect` from `@vercel/connect/eve`. */
export interface ConnectEveOptions {
  readonly connector: string;
  readonly principalType?: "app" | "user";
  readonly createSubject: (
    principal: EveConnectionPrincipal,
    context: { readonly url?: string },
  ) => CredentialSubject;
  readonly [option: string]: unknown;
}

/** `connect` from `@vercel/connect/eve`, typed by what `connectAuth` calls. */
export type ConnectEveFunction<Authorization> = (
  options: ConnectEveOptions,
) => Authorization;

export interface ConnectAuthOptions {
  /** The Vercel Connect connector: a `scl_` key or a UID. */
  readonly connector: string;
  /** The project's API URL: it names the issuer of the user's grant. */
  readonly supabaseUrl: string;
  /** Default `user`. `app` uses the connector's app credential. */
  readonly principalType?: "app" | "user";
  /**
   * Other options of `connect`, such as `tokenParams`, `validate`,
   * `autoProvision` or `displayName`, passed through as they are.
   */
  readonly connect?: Readonly<Record<string, unknown>>;
}

/**
 * `connect` from `@vercel/connect/eve` for a Supabase app: a user principal
 * maps to the Connect subject `vercelConnectCredentials` uses (the Auth user id
 * under the project's Auth URL as issuer), so an account a user connects in
 * your routes also works in the agent's connections, and the reverse. Pass
 * `connect` in, so the module loads where eve loads it:
 *
 * ```ts
 * import { connect } from "@vercel/connect/eve";
 * auth: connectAuth(connect, { connector: "linear", supabaseUrl });
 * ```
 *
 * The result is what `connect` returns, with its `evict` and `vercelConnect`
 * members, so eve evicts a rejected token as it does for a plain `connect`.
 */
export function connectAuth<Authorization>(
  connect: ConnectEveFunction<Authorization>,
  options: ConnectAuthOptions,
): Authorization {
  const { connector, supabaseUrl, principalType, connect: extra } = options;

  return connect({
    ...extra,
    connector,
    ...(principalType === undefined ? {} : { principalType }),
    createSubject: (principal) =>
      principal.type === "app"
        ? { type: "app" }
        : connectSubject({ id: principal.id }, { supabaseUrl }),
  });
}
