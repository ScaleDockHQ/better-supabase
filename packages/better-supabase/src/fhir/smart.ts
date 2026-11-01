import type { Result } from "../core/result.ts";

import { toBase64Url } from "../core/base64.ts";
import { dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";
import { err, ok } from "../core/result.ts";

/** What `.well-known/smart-configuration` says (SMART App Launch 2.2). */
export interface SmartConfiguration {
  readonly authorizationEndpoint: string;
  readonly tokenEndpoint: string;
  readonly capabilities: readonly string[];
  readonly codeChallengeMethods: readonly string[];
  readonly scopesSupported?: readonly string[];
}

/** What one launch needs to keep between the redirect and the callback. */
export interface SmartPending {
  readonly iss: string;
  readonly clientId: string;
  readonly redirectUri: string;
  readonly codeVerifier: string;
  readonly tokenEndpoint: string;
  /** When the pending launch stops being valid, in milliseconds. */
  readonly expiresAt: number;
}

/**
 * Keeps the PKCE verifier and the platform's endpoints between the redirect and
 * the callback, keyed by `state`. Versioned: a breaking change ships a new
 * `apiVersion`. Back it with a cookie, a table or a cache; `take` must delete
 * what it returns, so a callback works once.
 */
export interface SmartLaunchStore {
  readonly apiVersion: 1;
  save(state: string, pending: SmartPending): Promise<void>;
  take(state: string): Promise<SmartPending | undefined>;
}

/** Checks a store's `apiVersion` before the app uses it. */
export function smartLaunchStoreOf(store: SmartLaunchStore): SmartLaunchStore {
  const version: unknown = store.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `SMART launch store targets store API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the store for API 1.`,
    );
  }

  return store;
}

/** The token response of a SMART launch (SMART App Launch 2.2). */
export interface SmartTokens {
  readonly accessToken: string;
  readonly tokenType: string;
  readonly expiresIn?: number | undefined;
  readonly refreshToken?: string | undefined;
  readonly idToken?: string | undefined;
  /** The scopes the server granted, which can be fewer than requested. */
  readonly scope: readonly string[];
  /** The patient in context, when the scope `launch/patient` was granted. */
  readonly patient?: string | undefined;
  readonly encounter?: string | undefined;
  readonly needPatientBanner?: boolean | undefined;
  readonly smartStyleUrl?: string | undefined;
  readonly fhirContext?: readonly unknown[] | undefined;
}

function failure<T>(hint: string, message: string): Result<T> {
  return err(dbError("unauthorized", message, { hint }));
}

function strings(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

/**
 * Reads the server's SMART configuration from
 * `<iss>/.well-known/smart-configuration`. A server that does not offer `S256`
 * is refused, because a launch without PKCE is not one this helper starts.
 */
export async function fetchSmartConfiguration(
  iss: string,
  fetcher: typeof fetch = fetch,
): Promise<Result<SmartConfiguration>> {
  const response = await fetcher(
    `${iss.replace(/\/+$/, "")}/.well-known/smart-configuration`,
    { headers: { accept: "application/json" } },
  );

  if (!response.ok) {
    return failure(
      "SMART_CONFIGURATION",
      `The server has no SMART configuration (${response.status})`,
    );
  }

  const body: unknown = await response.json().catch(() => undefined);
  const authorization = isRecord(body) ? body["authorization_endpoint"] : "";
  const token = isRecord(body) ? body["token_endpoint"] : "";

  if (
    !isRecord(body) ||
    typeof authorization !== "string" ||
    typeof token !== "string" ||
    authorization === "" ||
    token === ""
  ) {
    return failure(
      "SMART_CONFIGURATION",
      "The SMART configuration lacks an authorization or token endpoint",
    );
  }

  const methods = strings(body["code_challenge_methods_supported"]);

  if (!methods.includes("S256")) {
    return failure("SMART_PKCE", "The server does not support PKCE with S256");
  }

  const scopes = strings(body["scopes_supported"]);

  return ok({
    authorizationEndpoint: authorization,
    tokenEndpoint: token,
    capabilities: strings(body["capabilities"]),
    codeChallengeMethods: methods,
    ...(scopes.length === 0 ? {} : { scopesSupported: scopes }),
  });
}

/** The S256 challenge of a PKCE verifier (RFC 7636). */
export async function pkceChallenge(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(verifier),
  );

  return toBase64Url(new Uint8Array(digest));
}

function randomToken(bytes: number): string {
  return toBase64Url(crypto.getRandomValues(new Uint8Array(bytes)));
}

export interface SmartLaunchOptions {
  readonly clientId: string;
  /** The redirect URI registered with the server. */
  readonly redirectUri: string;
  /** Space-separated scopes, such as `launch openid fhirUser patient/*.rs`. */
  readonly scope: string;
  readonly store: SmartLaunchStore;
  /** Servers the app launches from. A launch from another `iss` is refused. */
  readonly allowedIssuers: readonly string[];
  readonly fetch?: typeof fetch;
  /** Seconds a redirect stays valid. Default 600. */
  readonly ttlSeconds?: number;
  /** A confidential client's secret, sent as HTTP Basic at the token endpoint. */
  readonly clientSecret?: string;
  /** The time, in milliseconds. Default now. */
  readonly now?: () => number;
}

export interface SmartLaunch {
  /**
   * Starts an EHR launch (`?iss=...&launch=...`) or a standalone launch (no
   * `launch`): returns the authorization URL to redirect to.
   */
  begin(input: {
    readonly iss: string;
    readonly launch?: string;
  }): Promise<Result<string>>;
  /**
   * Finishes the launch at the redirect URI: checks `state`, exchanges the code
   * with the stored verifier and returns the tokens with the context.
   */
  complete(input: {
    readonly code: string;
    readonly state: string;
  }): Promise<Result<SmartTokens>>;
}

function tokensOf(body: unknown): Result<SmartTokens> {
  if (!isRecord(body)) {
    return failure("SMART_TOKEN", "The token response is not JSON");
  }

  const accessToken = body["access_token"];
  const tokenType = body["token_type"];

  if (typeof accessToken !== "string" || typeof tokenType !== "string") {
    return failure("SMART_TOKEN", "The token response lacks an access token");
  }

  const text = (key: string): string | undefined => {
    const value = body[key];

    return typeof value === "string" && value !== "" ? value : undefined;
  };

  const expiresIn = body["expires_in"];
  const banner = body["need_patient_banner"];
  const context = body["fhirContext"];

  return ok({
    accessToken,
    tokenType,
    ...(typeof expiresIn === "number" ? { expiresIn } : {}),
    ...(text("refresh_token") === undefined
      ? {}
      : { refreshToken: text("refresh_token") }),
    ...(text("id_token") === undefined ? {} : { idToken: text("id_token") }),
    scope: (text("scope") ?? "").split(" ").filter(Boolean),
    ...(text("patient") === undefined ? {} : { patient: text("patient") }),
    ...(text("encounter") === undefined
      ? {}
      : { encounter: text("encounter") }),
    ...(typeof banner === "boolean" ? { needPatientBanner: banner } : {}),
    ...(text("smart_style_url") === undefined
      ? {}
      : { smartStyleUrl: text("smart_style_url") }),
    ...(Array.isArray(context) ? { fhirContext: context } : {}),
  });
}

/**
 * The SMART on FHIR (App Launch 2.2) client side for an EHR or standalone
 * launch with PKCE and the authorization-code flow. It bundles no SDK and keeps
 * nothing itself: the `store` holds the verifier between the two requests.
 * Backend services (client credentials with a signed JWT) and token refresh are
 * not covered.
 */
export function createSmartLaunch(options: SmartLaunchOptions): SmartLaunch {
  const fetcher = options.fetch ?? fetch;
  const now = options.now ?? Date.now;
  const store = smartLaunchStoreOf(options.store);

  return {
    async begin({ iss, launch }) {
      if (!options.allowedIssuers.includes(iss)) {
        return failure("SMART_ISSUER", "The launch is from an unknown server");
      }

      const configuration = await fetchSmartConfiguration(iss, fetcher);

      if (!configuration.ok) {
        return configuration;
      }

      const state = randomToken(24);
      const codeVerifier = randomToken(48);

      await store.save(state, {
        iss,
        clientId: options.clientId,
        redirectUri: options.redirectUri,
        codeVerifier,
        tokenEndpoint: configuration.data.tokenEndpoint,
        expiresAt: now() + (options.ttlSeconds ?? 600) * 1000,
      });

      const url = new URL(configuration.data.authorizationEndpoint);

      url.searchParams.set("response_type", "code");
      url.searchParams.set("client_id", options.clientId);
      url.searchParams.set("redirect_uri", options.redirectUri);
      url.searchParams.set(
        "scope",
        launch === undefined || options.scope.split(" ").includes("launch")
          ? options.scope
          : `launch ${options.scope}`,
      );
      url.searchParams.set("state", state);
      url.searchParams.set("aud", iss);
      url.searchParams.set("code_challenge", await pkceChallenge(codeVerifier));
      url.searchParams.set("code_challenge_method", "S256");

      if (launch !== undefined) {
        url.searchParams.set("launch", launch);
      }

      return ok(url.toString());
    },

    async complete({ code, state }) {
      const pending = await store.take(state);

      if (pending === undefined || pending.expiresAt < now()) {
        return failure("SMART_STATE", "The launch state is unknown or expired");
      }

      const headers: Record<string, string> = {
        "content-type": "application/x-www-form-urlencoded",
        accept: "application/json",
      };

      const form = new URLSearchParams({
        grant_type: "authorization_code",
        code,
        redirect_uri: pending.redirectUri,
        code_verifier: pending.codeVerifier,
      });

      if (options.clientSecret === undefined) {
        form.set("client_id", pending.clientId);
      } else {
        headers["authorization"] =
          `Basic ${btoa(`${encodeURIComponent(pending.clientId)}:${encodeURIComponent(options.clientSecret)}`)}`;
      }

      const response = await fetcher(pending.tokenEndpoint, {
        method: "POST",
        headers,
        body: form,
      });

      if (!response.ok) {
        return failure(
          "SMART_TOKEN",
          `The token endpoint answered ${response.status}`,
        );
      }

      return tokensOf(await response.json().catch(() => undefined));
    },
  };
}
