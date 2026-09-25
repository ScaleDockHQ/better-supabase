import { createServerClient } from '@supabase/ssr';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

import { stack } from './stack-config.ts';

export { stack };

export const ACME = '00000000-0000-4000-8000-000000000001';
export const OTHER = '00000000-0000-4000-8000-000000000002';

export async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${stack.url}/auth/v1/health`, {
      headers: { apikey: stack.publishableKey },
      signal: AbortSignal.timeout(1000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

export const admin: SupabaseClient = createClient(stack.url, stack.secretKey, {
  auth: { persistSession: false },
});

export interface TestUser {
  readonly id: string;
  readonly email: string;
  readonly password: string;
  readonly accessToken: string;
  /** A `Cookie` header with the session as `@supabase/ssr` writes it. */
  readonly cookie: () => Promise<string>;
  readonly remove: () => Promise<void>;
}

/**
 * A confirmed user in `orgId` (via `app_metadata.org_id`), signed in with a
 * password. `role` lands in `app_metadata.user_role`.
 */
export async function createUser(
  orgId: string,
  options: { readonly role?: 'admin' | 'member' } = {},
): Promise<TestUser> {
  const email = `e2e-${crypto.randomUUID()}@example.com`;
  const password = 'correct horse battery staple';
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: {
      org_id: orgId,
      ...(options.role ? { user_role: options.role } : {}),
    },
  });
  if (error) throw error;
  const client = createClient(stack.url, stack.publishableKey, {
    auth: { persistSession: false },
  });
  const { data: signIn, error: signInError } =
    await client.auth.signInWithPassword({ email, password });
  if (signInError) throw signInError;
  return {
    id: data.user.id,
    email,
    password,
    accessToken: signIn.session.access_token,
    cookie: async () => {
      const jar = new Map<string, string>();
      const server = createServerClient(stack.url, stack.publishableKey, {
        cookies: {
          getAll: () => [...jar].map(([name, value]) => ({ name, value })),
          setAll: (cookies) => {
            for (const cookie of cookies) jar.set(cookie.name, cookie.value);
          },
        },
      });
      const { error: cookieError } = await server.auth.signInWithPassword({
        email,
        password,
      });
      if (cookieError) throw cookieError;
      return [...jar]
        .map(([name, value]) => `${name}=${encodeURIComponent(value)}`)
        .join('; ');
    },
    remove: async () => {
      await admin.auth.admin.deleteUser(data.user.id);
    },
  };
}

/** Deletes rows created during a test, bypassing RLS. */
export function cleanup(table: string): {
  track: (id: string) => void;
  run: () => Promise<void>;
} {
  const ids: string[] = [];
  return {
    track: (id) => void ids.push(id),
    run: async () => {
      if (ids.length > 0) await admin.from(table).delete().in('id', ids);
    },
  };
}
