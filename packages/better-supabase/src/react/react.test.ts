import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';

import { createBrowser } from '../client/index.ts';
import { defineSupabase } from '../core/define.ts';
import { capturingClient } from '../fixtures/client.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { BetterSupabaseProvider, createHooks, useAuth } from './index.ts';

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
});
