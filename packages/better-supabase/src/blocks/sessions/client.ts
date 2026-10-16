import type { Result } from "../../core/result.ts";
import type { AuthReply } from "../auth-reply.ts";
import type { AuthPort, Controller } from "../controller.ts";

import { toInstant } from "../../core/block-helpers.ts";
import { type DbError, dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";
import { authResult } from "../auth-reply.ts";
import { defineController, whileSignedIn } from "../controller.ts";

/** An OAuth client as the Auth OAuth server describes it. */
export interface RawOAuthClient {
  readonly id: string;
  readonly name: string;
  readonly uri?: string;
  readonly logo_uri?: string;
}

/** The part of `supabase.auth.oauth` the consent controllers call. */
export interface OAuthApi {
  getAuthorizationDetails(authorizationId: string): PromiseLike<
    AuthReply<
      | {
          readonly authorization_id: string;
          readonly redirect_uri: string;
          readonly client: RawOAuthClient;
          readonly user: { readonly id: string; readonly email: string };
          readonly scope: string;
        }
      | { readonly redirect_url: string }
    >
  >;
  approveAuthorization(
    authorizationId: string,
    options?: { skipBrowserRedirect?: boolean },
  ): PromiseLike<AuthReply<{ readonly redirect_url: string }>>;
  denyAuthorization(
    authorizationId: string,
    options?: { skipBrowserRedirect?: boolean },
  ): PromiseLike<AuthReply<{ readonly redirect_url: string }>>;
  listGrants(): PromiseLike<
    AuthReply<
      readonly {
        readonly client: RawOAuthClient;
        readonly scopes: readonly string[];
        readonly granted_at: string;
      }[]
    >
  >;
  revokeGrant(options: { clientId: string }): PromiseLike<AuthReply<unknown>>;
}

export interface OAuthClientInfo {
  readonly id: string;
  readonly name: string;
  readonly uri: string | undefined;
  readonly logoUri: string | undefined;
}

/** An authorization request waiting for the user's decision. */
export interface OAuthConsentRequest {
  readonly authorizationId: string;
  readonly client: OAuthClientInfo;
  readonly user: { readonly id: string; readonly email: string };
  readonly scopes: readonly string[];
  /** The redirect URI the client registered. */
  readonly redirectUri: string;
  /** Its host, to show where approving sends the user. */
  readonly redirectHost: string;
}

const filled = (value: string | null | undefined): string | undefined =>
  value === null || value === undefined || value === "" ? undefined : value;

const clientInfo = (raw: RawOAuthClient): OAuthClientInfo => ({
  id: raw.id,
  name: raw.name,
  uri: filled(raw.uri),
  logoUri: filled(raw.logo_uri),
});

const hostOf = (uri: string): string => {
  try {
    return new URL(uri).host;
  } catch {
    return uri;
  }
};

type Details = Result<OAuthConsentRequest | { readonly redirectUrl: string }>;

/**
 * Reads per authorization id. A request the user approved before is used up
 * by its first read, so a second controller for the same id (React Strict
 * Mode mounts twice) has to share the answer.
 */
const reads = new Map<string, Promise<Details>>();

async function readDetails(
  oauth: OAuthApi,
  authorizationId: string,
): Promise<Details> {
  const result = await authResult(() =>
    oauth.getAuthorizationDetails(authorizationId),
  );
  if (!result.ok) return result;
  const data = result.data;
  if (!("authorization_id" in data)) {
    return ok({ redirectUrl: data.redirect_url });
  }
  return ok({
    authorizationId: data.authorization_id,
    client: clientInfo(data.client),
    user: data.user,
    scopes: data.scope.split(" ").filter((scope) => scope !== ""),
    redirectUri: data.redirect_uri,
    redirectHost: hostOf(data.redirect_uri),
  });
}

export interface OAuthConsentControllerOptions {
  /** `supabase.auth.oauth` of the browser client. */
  readonly oauth: OAuthApi;
  readonly auth: AuthPort;
  /** `authorization_id` from the consent page's URL; `undefined` loads nothing. */
  readonly authorizationId: string | undefined;
  /**
   * Leaves for a `redirect_url` that Auth returned: after a decision, or at
   * once for a client the user approved before. Default:
   * `window.location.assign`.
   */
  readonly redirect?: (url: string) => void;
}

export interface OAuthConsentSnapshot {
  /** The request to approve or deny; `undefined` while it loads or after a redirect. */
  readonly request: OAuthConsentRequest | undefined;
  /** The URL the controller sent the browser to. */
  readonly redirectUrl: string | undefined;
  /** The decision in flight; it stays set while the browser leaves. */
  readonly deciding: "approve" | "deny" | undefined;
  readonly error: DbError | undefined;
}

export interface OAuthConsentActions {
  /** Approves the request and goes to the client with a code. */
  readonly approve: () => Promise<Result<string>>;
  /** Denies the request and goes to the client with `access_denied`. */
  readonly deny: () => Promise<Result<string>>;
}

export type OAuthConsentController = Controller<
  OAuthConsentSnapshot,
  OAuthConsentActions
>;

const assign = (url: string): void => {
  globalThis.location.assign(url);
};

/**
 * The consent page of the Supabase Auth OAuth server: it reads the request
 * for `authorizationId`, and `approve` or `deny` send the browser to the
 * `redirect_url` that Auth returns, never to a URL from the page.
 */
export function createOAuthConsentController(
  options: OAuthConsentControllerOptions,
): OAuthConsentController {
  const { oauth, authorizationId } = options;
  const redirect = options.redirect ?? assign;
  return defineController<OAuthConsentSnapshot, OAuthConsentActions>(
    {
      request: undefined,
      redirectUrl: undefined,
      deciding: undefined,
      error: undefined,
    },
    (state) => {
      const leave = (url: string): void => {
        state.set({ request: undefined, redirectUrl: url });
        redirect(url);
      };
      const load = async (id: string): Promise<void> => {
        let read = reads.get(id);
        if (read === undefined) {
          read = readDetails(oauth, id);
          reads.set(id, read);
        }
        const run = state.run();
        const result = await read;
        if (run !== state.run()) return;
        if (!result.ok) {
          reads.delete(id);
          state.set({ error: result.error });
          return;
        }
        if ("redirectUrl" in result.data) {
          leave(result.data.redirectUrl);
          return;
        }
        state.set({ request: result.data, error: undefined });
      };
      const decide = async (
        decision: "approve" | "deny",
      ): Promise<Result<string>> => {
        const id = state.get().request?.authorizationId;
        if (id === undefined || state.get().deciding !== undefined) {
          return err(
            dbError("invalid_input", "No authorization request to decide"),
          );
        }
        state.set({ deciding: decision, error: undefined });
        const result = await authResult(() =>
          decision === "approve"
            ? oauth.approveAuthorization(id, { skipBrowserRedirect: true })
            : oauth.denyAuthorization(id, { skipBrowserRedirect: true }),
        );
        if (!result.ok) {
          state.set({ deciding: undefined, error: result.error });
          return result;
        }
        reads.delete(id);
        leave(result.data.redirect_url);
        return ok(result.data.redirect_url);
      };
      return {
        actions: {
          approve: () => decide("approve"),
          deny: () => decide("deny"),
        },
        start: () =>
          whileSignedIn(options.auth, () => {
            if (authorizationId !== undefined) void load(authorizationId);
            return;
          }),
      };
    },
  );
}

/** A client the user approved. */
export interface OAuthGrant {
  readonly client: OAuthClientInfo;
  readonly scopes: readonly string[];
  readonly grantedAt: Temporal.Instant;
}

export interface OAuthGrantsControllerOptions {
  /** `supabase.auth.oauth` of the browser client. */
  readonly oauth: OAuthApi;
  readonly auth: AuthPort;
}

export interface OAuthGrantsSnapshot {
  /** Newest first; `undefined` until the first load. */
  readonly grants: readonly OAuthGrant[] | undefined;
  /** The client ids with a revoke in flight. */
  readonly revoking: readonly string[];
  readonly error: DbError | undefined;
}

export interface OAuthGrantsActions {
  /**
   * Disconnects a client: its sessions end and its refresh tokens stop
   * working. An access token it holds stays valid until it expires.
   */
  readonly revoke: (clientId: string) => Promise<Result<boolean>>;
  readonly refresh: () => Promise<void>;
}

export type OAuthGrantsController = Controller<
  OAuthGrantsSnapshot,
  OAuthGrantsActions
>;

/** The OAuth clients (such as MCP clients) the user approved, for a connected agents list. */
export function createOAuthGrantsController(
  options: OAuthGrantsControllerOptions,
): OAuthGrantsController {
  const { oauth } = options;
  return defineController<OAuthGrantsSnapshot, OAuthGrantsActions>(
    { grants: undefined, revoking: [], error: undefined },
    (state) => {
      let ticket = 0;
      const refresh = async (): Promise<void> => {
        const request = ++ticket;
        const result = await authResult(() => oauth.listGrants());
        if (request !== ticket) return;
        if (!result.ok) {
          state.set({ error: result.error });
          return;
        }
        state.set({
          grants: result.data
            .map((grant): OAuthGrant => ({
              client: clientInfo(grant.client),
              scopes: grant.scopes,
              grantedAt: toInstant(grant.granted_at),
            }))
            .toSorted(
              (a, b) =>
                b.grantedAt.epochMilliseconds - a.grantedAt.epochMilliseconds,
            ),
          error: undefined,
        });
      };
      return {
        actions: {
          refresh,
          revoke: async (clientId) => {
            state.set((current) => ({
              revoking: [...current.revoking, clientId],
              error: undefined,
            }));
            const result = await authResult(() =>
              oauth.revokeGrant({ clientId }),
            );
            state.set((current) => ({
              revoking: current.revoking.filter((each) => each !== clientId),
              ...(result.ok ? {} : { error: result.error }),
            }));
            if (!result.ok) return result;
            await refresh();
            return ok(true);
          },
        },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();
            return;
          }),
      };
    },
  );
}
