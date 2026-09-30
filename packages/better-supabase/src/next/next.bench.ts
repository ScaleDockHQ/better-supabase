/**
 * Twelve islands in one render, each its own private-cache scope.
 * Run with `pnpm --filter better-supabase bench`.
 */
import { clearVerifiedTokens } from "../auth/resolve.ts";
import { defineSupabase } from "../core/define.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createServer } from "../server/server.ts";
import { createTestSigner } from "../testing/jwt.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const ISLANDS = 12;
const RENDERS = 200;

const signer = await createTestSigner();
const token = await signer.sign({
  sub: "11111111-1111-4111-8111-111111111111",
});
const server = createServer(defineSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks as never },
});
const request = (): Request =>
  new Request("https://app.test/", {
    headers: { authorization: `Bearer ${token}` },
  });
/** Four islands query; the other eight only read the session. */
const readsData = (island: number): boolean => island % 3 === 0;

async function before(): Promise<void> {
  for (let island = 0; island < ISLANDS; island++) {
    clearVerifiedTokens();
    const ctx = await server.context(request());
    void ctx.supabase;
    void ctx.db;
  }
}

async function after(): Promise<void> {
  for (let island = 0; island < ISLANDS; island++) {
    const ctx = await server.context(request());
    if (readsData(island)) void ctx.db;
  }
}

async function measure(render: () => Promise<void>): Promise<number> {
  for (let warm = 0; warm < 20; warm++) await render();
  const started = performance.now();
  for (let run = 0; run < RENDERS; run++) await render();
  return (performance.now() - started) / RENDERS;
}

const slow = await measure(before);
const fast = await measure(after);
console.table({
  before: {
    verifications: ISLANDS,
    clients: ISLANDS,
    "ms per render": slow.toFixed(2),
  },
  after: { verifications: 1, clients: 4, "ms per render": fast.toFixed(2) },
});
console.log(`${(slow / fast).toFixed(1)}x faster`);
