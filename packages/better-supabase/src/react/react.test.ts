import { createElement, Suspense } from 'react';
import { renderToReadableStream, renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';

import type { AuthSession } from '../auth/view.ts';

import { createBrowser } from '../client/index.ts';
import { defineSupabase } from '../core/define.ts';
import { capturingClient } from '../fixtures/client.ts';
import { schema } from '../fixtures/generated-camel.ts';
import {
  BetterSupabaseProvider,
  createHooks,
  SessionProvider,
  useAuth,
  useSession,
} from './index.ts';

const sb = defineSupabase(schema);
const browser = createBrowser(sb, { client: capturingClient().client });
const hooks = createHooks<typeof browser>();

function Status() {
  const auth = useAuth();
  const db = hooks.useDb();
  return createElement(
    'p',
    null,
    `${auth.status}:${String(db.$context.actor?.kind)}`,
  );
}

describe('react', () => {
  it('provides the browser to hooks, loading on the server', () => {
    const html = renderToString(
      createElement(BetterSupabaseProvider, { browser }, createElement(Status)),
    );
    expect(html).toBe('<p>loading:anon</p>');
  });

  it('explains a missing provider', () => {
    expect(() => renderToString(createElement(Status))).toThrow(
      /BetterSupabaseProvider/,
    );
  });

  it('resolves the session promise inside Suspense', async () => {
    function Who() {
      const session = useSession();
      return createElement(
        'p',
        null,
        session.kind === 'user' ? session.user.email : session.kind,
      );
    }
    const render = async (session: AuthSession) => {
      const stream = await renderToReadableStream(
        createElement(
          Suspense,
          { fallback: 'loading' },
          createElement(
            SessionProvider,
            { sessionPromise: Promise.resolve(session) },
            createElement(Who),
          ),
        ),
      );
      await stream.allReady;
      return new Response(stream).text();
    };

    expect(
      await render({
        kind: 'user',
        user: { id: 'u1', email: 'ada@example.com' },
        claims: { sub: 'u1' },
        expiresAt: null,
      }),
    ).toContain('<p>ada@example.com</p>');
    expect(await render({ kind: 'anon', reason: 'none' })).toContain(
      '<p>anon</p>',
    );
  });

  it('explains a missing SessionProvider', () => {
    function Who() {
      useSession();
      return null;
    }
    expect(() => renderToString(createElement(Who))).toThrow(/SessionProvider/);
  });
});
