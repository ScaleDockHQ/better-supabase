import { ErrorCode } from "@openfeature/server-sdk";
import { withOpenFeature } from "@supabase-labs/middleware-openfeature";
import { pipeline } from "@supabase/middleware";
import { describe, expect, it } from "vitest";

import {
  createFlagClient,
  type FlagContextSource,
  flagContext,
} from "../../../src/blocks/flags/index.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { withBetterSupabase } from "../../../src/server/composite.ts";
import { createServer } from "../../../src/server/server.ts";
import { createTestSigner } from "../../../src/testing/jwt.ts";
import { schema } from "../../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();
const server = createServer(defineSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks as never },
  prefetchJwks: false,
});

const client = createFlagClient({
  definitions: [
    {
      key: "new_editor",
      type: "boolean",
      variants: { on: true, off: false },
      defaultVariant: "off",
      enabled: true,
      rules: [{ variant: "on", roles: ["admin"] }],
      rolloutPercentage: 0,
      rolloutVariant: undefined,
      overrides: [],
    },
  ],
  errorCodes: ErrorCode,
});

const fetch = pipeline(
  [
    withBetterSupabase(server),
    withOpenFeature({
      client,
      flags: { new_editor: false },
      context: (_req: Request, ctx: FlagContextSource) => flagContext(ctx),
    }),
  ],
  (_req, ctx) => Promise.resolve(Response.json(ctx.flags)),
);

const request = (token: string) =>
  new Request("https://api.test/notes", {
    headers: { authorization: `Bearer ${token}` },
  });

describe("withOpenFeature after withBetterSupabase", () => {
  it("evaluates flags with the verified claims as the context", async () => {
    const admin = await signer.sign({
      sub: USER,
      tenant_id: "org-1",
      memberships: { "org-1": "admin" },
    });
    expect(await (await fetch(request(admin))).json()).toEqual({
      new_editor: true,
    });
    const member = await signer.sign({
      sub: USER,
      tenant_id: "org-1",
      memberships: { "org-1": "member" },
    });
    expect(await (await fetch(request(member))).json()).toEqual({
      new_editor: false,
    });
  });
});
