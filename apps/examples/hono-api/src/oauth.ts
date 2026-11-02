import type {
  AuthorizationCodeRedemption,
  AuthorizationCodeRequest,
} from "better-supabase/blocks/oauth-server";

import { serviceBlocks } from "./blocks";

const OWNER = { type: "app", id: "default" } as const;
const ACCESS_TOKEN_SECONDS = 600;

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

/** An RFC 6749 section 5.2 error: token endpoint errors are not Problem Details. */
function tokenError(
  error: string,
  description: string,
  status = 400,
): Response {
  const headers = new Headers({ "cache-control": "no-store" });

  if (status === 401) {
    headers.set("www-authenticate", 'Basic realm="oauth"');
  }

  return Response.json(
    { error, error_description: description },
    { status, headers },
  );
}

/**
 * `client_secret_basic` (RFC 6749 section 2.3.1), then `client_secret_post`,
 * then a public client.
 */
function clientCredentials(
  request: Request,
  form: URLSearchParams,
): { readonly clientId: string; readonly secret: string | null } | undefined {
  const header = request.headers.get("authorization");

  if (header?.toLowerCase().startsWith("basic ")) {
    const decoded = atob(header.slice(6).trim());
    const colon = decoded.indexOf(":");

    if (colon === -1) {
      return undefined;
    }

    return {
      clientId: decodeURIComponent(decoded.slice(0, colon)),
      secret: decodeURIComponent(decoded.slice(colon + 1)),
    };
  }

  const clientId = form.get("client_id");

  return clientId ? { clientId, secret: form.get("client_secret") } : undefined;
}

/**
 * Stores a code for the signed-in user once they consented, and returns the
 * redirect the client receives (RFC 6749 section 4.1.2).
 */
export async function authorize(input: {
  readonly userId: string;
  readonly params: URLSearchParams;
}): Promise<URL> {
  const { params, userId } = input;
  const redirectUri = params.get("redirect_uri") ?? "";
  const scope = params.get("scope");

  const codeRequest: Mutable<AuthorizationCodeRequest> = {
    clientId: params.get("client_id") ?? "",
    userId,
    redirectUri,
    codeChallenge: params.get("code_challenge") ?? "",
    codeChallengeMethod: params.get("code_challenge_method") ?? "",
    resource: params.getAll("resource"),
  };

  if (scope) {
    codeRequest.scope = scope;
  }

  const issued = await serviceBlocks()
    .oauth.createAuthorizationCode(codeRequest)
    .orThrow();

  const redirect = new URL(redirectUri);
  redirect.searchParams.set("code", issued.code);
  const state = params.get("state");

  if (state) {
    redirect.searchParams.set("state", state);
  }

  return redirect;
}

/**
 * The token endpoint for the `authorization_code` grant, issuing RFC 9068
 * access tokens.
 */
export async function token(request: Request): Promise<Response> {
  const form = new URLSearchParams(await request.text());

  if (form.get("grant_type") !== "authorization_code") {
    return tokenError(
      "unsupported_grant_type",
      "Only authorization_code is supported",
    );
  }

  const credentials = clientCredentials(request, form);
  const { oauth, signingKeys } = serviceBlocks();

  const client = credentials
    ? await oauth
        .verifyClient({
          clientId: credentials.clientId,
          secret: credentials.secret,
        })
        .orThrow()
    : null;

  if (!credentials || !client) {
    return tokenError("invalid_client", "Unknown client or wrong secret", 401);
  }

  const redemption: Mutable<AuthorizationCodeRedemption> = {
    code: form.get("code") ?? "",
    clientId: client.clientId,
    codeVerifier: form.get("code_verifier") ?? "",
  };

  const redirectUri = form.get("redirect_uri");
  const resource = form.getAll("resource");

  if (redirectUri) {
    redemption.redirectUri = redirectUri;
  }

  if (resource.length > 0) {
    redemption.resource = resource;
  }

  const authorization = await oauth
    .redeemAuthorizationCode(redemption)
    .orThrow();

  if (!authorization) {
    return tokenError("invalid_grant", "The code is invalid or was used");
  }

  const issuer = new URL(request.url).origin;
  const now = Math.floor(Date.now() / 1000);

  const accessToken = await signingKeys
    .signer({ owner: OWNER, create: "Ed25519" })
    .signJwt(
      {
        iss: issuer,
        sub: authorization.userId,
        aud:
          authorization.resource.length > 0 ? authorization.resource : issuer,
        client_id: authorization.clientId,
        scope: authorization.scope,
        grant_id: authorization.grantId,
        jti: crypto.randomUUID(),
        iat: now,
        exp: now + ACCESS_TOKEN_SECONDS,
      },
      { typ: "at+jwt" },
    )
    .orThrow();

  return Response.json(
    {
      access_token: accessToken,
      token_type: "Bearer",
      expires_in: ACCESS_TOKEN_SECONDS,
      scope: authorization.scope,
    },
    { headers: { "cache-control": "no-store" } },
  );
}

/** The keys resource servers verify the access tokens with. */
export function jwks(): Promise<Response> {
  return serviceBlocks().signingKeys.jwksResponse({
    owner: OWNER,
    maxAge: 300,
  });
}
