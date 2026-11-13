import { posix } from "node:path";

import type { TemplateContext, TemplateFile } from "./templates.ts";

const join = (...parts: string[]): string =>
  posix.normalize(posix.join(...parts));

/**
 * The feature-sliced layout `init` writes for Next.js (ADR 0310, checked by
 * `scripts/check-app-architecture.ts`): a synchronous page that owns the
 * `<Suspense>` and turns `params` into plain values with `params.then()`, a
 * feature with `*-queries.ts` (`server-only`), `*-actions.ts` (`'use server'`)
 * and `*-cache.ts` (pure tags), async components with a sibling `*Skeleton`,
 * and an `AuthGate` in the layout. `server` is the path of
 * `lib/supabase/server`.
 */
export function nextAppFiles(
  context: TemplateContext,
  server: string,
  from: (file: string, to: string) => string,
): TemplateFile[] {
  const at = (...parts: string[]): string => join(context.srcDir, ...parts);

  const layout = at("app", "(app)", "layout.tsx");
  const page = at("app", "(app)", "page.tsx");
  const section = at("app", "(app)", "account", "[section]", "page.tsx");

  const gate = at("features", "auth", "components", "app-auth-gate.tsx");
  const authQueries = at("features", "auth", "auth-queries.ts");
  const authActions = at("features", "auth", "auth-actions.ts");
  const menu = at("features", "auth", "components", "account-menu.tsx");

  const accountQueries = at("features", "account", "account-queries.ts");
  const accountCache = at("features", "account", "account-cache.ts");

  const accountSection = at(
    "features",
    "account",
    "components",
    "account-section.tsx",
  );

  const shell = at("components", "app-shell-skeleton.tsx");

  return [
    {
      path: layout,
      contents: `import type { ReactNode } from 'react';

import { AppShellSkeleton } from '${from(layout, shell)}';
import { AppAuthGate } from '${from(layout, gate)}';

/** The layout stays synchronous: the gate streams the signed-in user. */
export default function AppLayout({ children }: { children: ReactNode }) {
  return (
    <AppAuthGate fallback={<AppShellSkeleton />}>{children}</AppAuthGate>
  );
}
`,
    },
    {
      path: page,
      contents: `import Link from 'next/link';

import { AccountMenu } from '${from(page, menu)}';

export default function HomePage() {
  return (
    <main>
      <AccountMenu />
      <Link href="/account/profile">Your account</Link>
    </main>
  );
}
`,
    },
    {
      path: section,
      contents: `import { Suspense } from 'react';

import {
  AccountSection,
  AccountSectionSkeleton,
} from '${from(section, accountSection)}';

/** The page owns the boundary and hands the feature a plain section name. */
export default function AccountPage({
  params,
}: {
  params: Promise<{ section: string }>;
}) {
  return (
    <Suspense fallback={<AccountSectionSkeleton />}>
      {params.then(({ section }) => (
        <AccountSection section={section} />
      ))}
    </Suspense>
  );
}
`,
    },
    {
      path: gate,
      contents: `import type { ReactNode } from 'react';

import { AuthGate } from 'better-supabase/next/auth-gate';

import { getUser } from '${from(gate, authQueries)}';

export function AppAuthGate({
  children,
  fallback,
}: {
  children: ReactNode;
  fallback: ReactNode;
}) {
  return (
    <AuthGate user={getUser} fallback={fallback} redirect="/sign-in">
      {children}
    </AuthGate>
  );
}
`,
    },
    {
      path: authQueries,
      contents: `import 'server-only';

import { bsb } from '${from(authQueries, server)}';

/** The signed-in user as plain data, kept in the App Shell for five minutes. */
export async function getUser() {
  'use cache: private';

  return bsb.user();
}
`,
    },
    {
      path: authActions,
      contents: `'use server';

import { bsb } from '${from(authActions, server)}';

export async function signOutAction(): Promise<void> {
  await bsb.signOut({ next: '/sign-in' });
}
`,
    },
    {
      path: menu,
      contents: `'use client';

import { useUser } from 'better-supabase/next/auth-gate';

import { signOutAction } from '${from(menu, authActions)}';

export function AccountMenu() {
  const user = useUser();

  return (
    <form action={signOutAction}>
      <span>{user?.email}</span>
      <button type="submit">Sign out</button>
    </form>
  );
}
`,
    },
    {
      path: accountCache,
      contents: `import { tagFor } from 'better-supabase/next';

/** The tag of one user's account entry; \`updateTag\` it after a write. */
export const accountTag = (userId: string): string =>
  tagFor('account', userId);
`,
    },
    {
      path: accountQueries,
      contents: `import 'server-only';

import { bsb } from '${from(accountQueries, server)}';
import { accountTag } from '${from(accountQueries, accountCache)}';

/** One account section of a user, kept until a write calls \`updateTag\`. */
export async function getAccountSection(userId: string, section: string) {
  'use cache: private';

  const { session } = await bsb.cached({
    life: 'max',
    tags: [accountTag(userId)],
  });

  return {
    section,
    email: session.kind === 'user' ? session.user.email : undefined,
  };
}
`,
    },
    {
      path: accountSection,
      contents: `import { getUser } from '${from(accountSection, authQueries)}';
import { getAccountSection } from '${from(accountSection, accountQueries)}';

export async function AccountSection({ section }: { section: string }) {
  const user = await getUser();
  const account = user ? await getAccountSection(user.id, section) : null;

  return (
    <section>
      <h1>{account?.section}</h1>
      <p>{account?.email}</p>
    </section>
  );
}

export function AccountSectionSkeleton() {
  return <section aria-busy="true" />;
}
`,
    },
    {
      path: shell,
      contents: `export function AppShellSkeleton() {
  return <div aria-busy="true" />;
}
`,
    },
  ];
}

/**
 * The PWA files `init` writes for Next.js: a manifest route, a service worker
 * that caches only public GET responses, its offline page, and the Web Push
 * keys in \`.env.example\`. \`createNextConfig\` serves \`/sw.js\` with
 * \`no-cache, no-store, must-revalidate\`.
 */
export function nextPwaFiles(context: TemplateContext): TemplateFile[] {
  const at = (...parts: string[]): string => join(context.srcDir, ...parts);

  return [
    {
      path: at("app", "manifest.ts"),
      contents: `import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'My app',
    short_name: 'App',
    start_url: '/',
    scope: '/',
    display: 'standalone',
    background_color: '#ffffff',
    theme_color: '#000000',
    icons: [],
  };
}
`,
    },
    {
      path: "public/sw.js",
      contents: `// One service worker per scope: offline shell and Web Push share this file.
const CACHE = 'shell-v1';
// Hashed build files stay across deploys: a tab on the previous build still
// needs its chunks. Bump the suffix only when the matching rule changes.
const STATIC_CACHE = 'next-static-v1';
const STATIC_MAX_ENTRIES = 512;
const OFFLINE = '/offline.html';

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.add(OFFLINE)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE && key !== STATIC_CACHE)
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

// Never store a private or no-store response, and never replay a POST:
// experimental.useOffline retries Server Actions.
const storable = (response) =>
  response.ok && !/private|no-store/i.test(response.headers.get('cache-control') ?? '');

// /_next/static/service-worker/ keeps a stable URL and must-revalidate; every
// other file under /_next/static is immutable per URL.
const isHashedStatic = (url) =>
  url.pathname.startsWith('/_next/static/') &&
  !url.pathname.startsWith('/_next/static/service-worker/');

const immutable = (response) =>
  storable(response) && /\\bimmutable\\b/i.test(response.headers.get('cache-control') ?? '');

async function cacheFirst(request) {
  const cache = await caches.open(STATIC_CACHE);
  const hit = await cache.match(request);

  if (hit) {
    return hit;
  }

  const response = await fetch(request);

  if (immutable(response)) {
    try {
      await cache.put(request, response.clone());
      const keys = await cache.keys();
      await Promise.all(
        keys.slice(0, Math.max(0, keys.length - STATIC_MAX_ENTRIES)).map((key) => cache.delete(key)),
      );
    } catch {
      await caches.delete(STATIC_CACHE);
    }
  }

  return response;
}

self.addEventListener('fetch', (event) => {
  const { request } = event;

  if (request.method !== 'GET') {
    return;
  }

  const url = new URL(request.url);

  if (url.origin === self.location.origin && isHashedStatic(url)) {
    event.respondWith(cacheFirst(request));

    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).catch(() => caches.match(OFFLINE)));
  }
});

self.addEventListener('push', (event) => {
  const data = event.data ? event.data.json() : {};
  event.waitUntil(self.registration.showNotification(data.title ?? 'Notification', { body: data.body }));
});
`,
    },
    {
      path: "public/offline.html",
      contents: `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Offline</title>
  </head>
  <body>
    <h1>You are offline</h1>
    <p>Reconnect to continue. Pending changes are sent when the connection returns.</p>
  </body>
</html>
`,
    },
    {
      path: ".env.example",
      contents: `# Web Push (generate a pair with \`npx web-push generate-vapid-keys\`)
NEXT_PUBLIC_VAPID_PUBLIC_KEY=
VAPID_PRIVATE_KEY=
`,
    },
  ];
}
