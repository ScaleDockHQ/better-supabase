import { type ChildProcess, execFileSync, spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { createServer } from 'node:net';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import {
  ACME,
  admin,
  createUser,
  OTHER,
  reachable,
  stack,
  type TestUser,
} from './stack.ts';

const app = fileURLToPath(
  new URL('../../../apps/examples/nextjs/', import.meta.url),
);
const env = {
  ...process.env,
  NEXT_PUBLIC_SUPABASE_URL: stack.url,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: stack.publishableKey,
  NEXT_TELEMETRY_DISABLED: '1',
};

async function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      server.close(() =>
        resolve(typeof address === 'object' && address ? address.port : 0),
      );
    });
  });
}

async function waitFor(url: string, server: ChildProcess): Promise<void> {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    if (server.exitCode !== null)
      throw new Error(`next start exited with ${String(server.exitCode)}`);
    try {
      await fetch(url, { signal: AbortSignal.timeout(1000) });
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  }
  throw new Error(`${url} did not come up`);
}

describe.skipIf(!(await reachable()))('nextjs example', () => {
  let server: ChildProcess;
  let base: string;
  let acme: TestUser;
  let other: TestUser;
  const name = `Next e2e ${crypto.randomUUID()}`;
  let id: string;

  beforeAll(async () => {
    if (!existsSync(`${app}.next/BUILD_ID`)) {
      execFileSync('pnpm', ['exec', 'next', 'build'], {
        cwd: app,
        env,
        stdio: 'ignore',
      });
    }
    const port = await freePort();
    base = `http://127.0.0.1:${String(port)}`;
    server = spawn(
      'pnpm',
      ['exec', 'next', 'start', '-p', String(port), '-H', '127.0.0.1'],
      {
        cwd: app,
        env,
        stdio: 'ignore',
      },
    );
    [acme, other] = await Promise.all([createUser(ACME), createUser(OTHER)]);
    const { data, error } = await admin
      .from('customers')
      .insert({ name, organization_id: ACME })
      .select('id')
      .single();
    if (error) throw error;
    id = (data as { id: string }).id;
    await waitFor(base, server);
  });

  afterAll(async () => {
    server?.kill();
    if (id) await admin.from('customers').delete().eq('id', id);
    await Promise.all([acme?.remove(), other?.remove()]);
  });

  const get = (path: string, headers: Record<string, string> = {}) =>
    fetch(`${base}${path}`, { headers });

  it('renders the signed-in user’s customers in a Server Component', async () => {
    const anonymous = await (await get('/')).text();
    expect(anonymous).toContain('Sign in');
    const page = await get('/', { cookie: await acme.cookie() });
    expect(page.status).toBe(200);
    expect(await page.text()).toContain(name);
    expect(
      await (await get('/', { cookie: await other.cookie() })).text(),
    ).not.toContain(name);
  });

  it('serves route handlers with bearer tokens and Problem Details', async () => {
    const list = await get(`/api/customers?q=${encodeURIComponent(name)}`, {
      authorization: `Bearer ${acme.accessToken}`,
    });
    expect(await list.json()).toEqual([
      { id, name, status: 'lead', organizationId: ACME },
    ]);

    const hidden = await get(`/api/customers/${id}`, {
      authorization: `Bearer ${other.accessToken}`,
    });
    expect(hidden.status).toBe(404);
    expect(hidden.headers.get('content-type')).toContain(
      'application/problem+json',
    );

    const anonymous = await get('/api/customers');
    expect(anonymous.status).toBe(401);
  });
});
