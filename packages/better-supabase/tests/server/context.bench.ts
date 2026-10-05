/**
 * `server.context()` latency for an anonymous request, a bearer token the
 * process has not verified yet, and one it has.
 * Run with `pnpm --filter better-supabase bench`.
 */
import { clearVerifiedTokens } from "../../src/auth/resolve.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { createServer } from "../../src/server/server.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const RUNS = 2000;
/**
 * A verified token must cost at most this share of a first verification;
 * past it, the per-process memo has stopped working.
 */
const MAX_WARM_SHARE = 0.5;

const signer = await createTestSigner();
const token = await signer.sign({
  sub: "11111111-1111-4111-8111-111111111111",
  org_id: "00000000-0000-4000-8000-000000000001",
});
const server = createServer(
  defineSupabase(schema).use(tenant({ claim: "org_id" })),
  {
    env: {
      url: PROJECT_URL,
      publishableKey: "sb_publishable_test",
      jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
    },
    auth: { jwks: signer.jwks as never },
  },
);
const anonymous = (): Request => new Request("https://app.test/");
const bearer = (): Request =>
  new Request("https://app.test/", {
    headers: { authorization: `Bearer ${token}` },
  });

async function measure(work: () => Promise<unknown>): Promise<number> {
  for (let warm = 0; warm < 200; warm++) await work();
  const started = performance.now();
  for (let run = 0; run < RUNS; run++) await work();
  return ((performance.now() - started) / RUNS) * 1000;
}

const anon = await measure(async () => {
  const ctx = await server.context(anonymous());
  return ctx.db;
});
const cold = await measure(async () => {
  clearVerifiedTokens();
  const ctx = await server.context(bearer());
  return ctx.db;
});
const warm = await measure(async () => {
  const ctx = await server.context(bearer());
  return ctx.db;
});
console.table({
  anonymous: { "µs per context": anon.toFixed(1) },
  "bearer, first verification": { "µs per context": cold.toFixed(1) },
  "bearer, verified": { "µs per context": warm.toFixed(1) },
});

if (warm > cold * MAX_WARM_SHARE) {
  console.error(
    `a verified token costs ${warm.toFixed(1)}µs, over ${String(MAX_WARM_SHARE * 100)}% of a first verification (${cold.toFixed(1)}µs).`,
  );
  process.exitCode = 1;
}
