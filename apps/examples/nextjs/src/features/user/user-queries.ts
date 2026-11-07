import "server-only";
import type { AuthSession } from "better-supabase/next";

import * as v from "valibot";

import type { Claims, Profile } from "@/lib/claims";

import { env } from "@/env";
import { avatarSrc } from "@/lib/buckets";
import { bsb } from "@/lib/supabase/server";

import { ProfileRow } from "./profile-row";

/**
 * The verified session, cached per browser session. The proxy refreshes the
 * token; this only verifies it locally against the JWKS, so it never calls the
 * Auth server. `bsb.cached()` tags the entry with the session tag, so
 * `bsb.evictSession` drops it, and keeps it no longer than the token. Call it
 * inside a `<Suspense>` boundary.
 */
export async function getSession(): Promise<AuthSession<Claims, Profile>> {
  "use cache: private";
  const { session } = await bsb.cached();

  return session;
}

export interface MyProfile {
  readonly fullName: string | null;
  readonly email: string | null;
  readonly username: string | null;
  /** The uploaded avatar's public URL, else the provider's picture. */
  readonly avatarUrl: string | null;
  /** The uploaded avatar's object path in the avatars bucket. */
  readonly avatarPath: string | null;
}

/**
 * The caller's row in the profiles SQL module. `bsb.evictSession` after a
 * profile update drops this entry with the rest of the user's cache.
 */
export async function getMyProfile(): Promise<MyProfile | null> {
  "use cache: private";
  const { db, session } = await bsb.cached();

  if (session.kind !== "user") {
    return null;
  }

  const found = await db.profiles.mine().orThrow();

  if (!found) {
    return null;
  }

  const row = v.parse(ProfileRow, found);

  return {
    fullName: row.full_name,
    email: row.email,
    username: row.username,
    avatarUrl: avatarSrc(db.$buckets.avatars, {
      avatarPath: row.avatar_path,
      avatarUrl: row.avatar_url,
    }),
    avatarPath: row.avatar_path,
  };
}

const AuthError = v.object({ msg: v.optional(v.string()) });

const User = v.object({
  factors: v.nullish(
    v.array(
      v.object({ id: v.string(), factor_type: v.string(), status: v.string() }),
    ),
  ),
});

const Grant = v.object({
  client: v.object({ id: v.string(), name: v.string() }),
  scopes: v.array(v.string()),
  granted_at: v.string(),
});

export type Grant = v.InferOutput<typeof Grant>;

/**
 * A GET on Supabase Auth as the caller. The server's user client takes the
 * token through `accessToken`, which turns `supabase.auth` off, so the reads
 * below call the endpoints `auth.mfa.listFactors()` and
 * `auth.oauth.listGrants()` use in the browser.
 */
async function authGet<S extends v.GenericSchema>(
  token: string,
  path: string,
  schema: S,
): Promise<v.InferOutput<S>> {
  const response = await fetch(
    `${env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1${path}`,
    {
      headers: {
        apikey: env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
        Authorization: `Bearer ${token}`,
      },
    },
  );

  const body: unknown = await response.json();

  if (!response.ok) {
    const parsed = v.safeParse(AuthError, body);
    throw new Error(
      (parsed.success ? parsed.output.msg : undefined) ??
        `Supabase Auth answered ${String(response.status)}`,
    );
  }

  return v.parse(schema, body);
}

/**
 * An Auth read that failed renders its message in the card instead of the error
 * page.
 */
export type AuthRead<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: string };

async function attempt<T>(read: () => Promise<T>): Promise<AuthRead<T>> {
  try {
    return { ok: true, value: await read() };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/** The caller's verified TOTP factor, or `null` without one. */
export async function getTotpFactorId(): Promise<AuthRead<string | null>> {
  "use cache: private";
  const { auth } = await bsb.cached();

  if (auth.kind !== "user") {
    return { ok: true, value: null };
  }

  const token = auth.token;

  return attempt(async () => {
    const user = await authGet(token, "/user", User);

    return (
      user.factors?.find(
        (factor) =>
          factor.factor_type === "totp" && factor.status === "verified",
      )?.id ?? null
    );
  });
}

/** The OAuth clients the caller approved on the consent page. */
export async function getOAuthGrants(): Promise<AuthRead<readonly Grant[]>> {
  "use cache: private";
  const { auth } = await bsb.cached();

  if (auth.kind !== "user") {
    return { ok: true, value: [] };
  }

  const token = auth.token;

  return attempt(() => authGet(token, "/user/oauth/grants", v.array(Grant)));
}
