// oxlint-disable-next-line eslint/no-restricted-imports -- anthropicMemory takes the provider's tools, so the test needs their real type.
import type { anthropic } from "@ai-sdk/anthropic";
import type {
  CommonPowerSyncDatabase,
  PowerSyncBackendConnector,
} from "@powersync/common";
import type * as Connect from "@vercel/connect";

import { describe, expectTypeOf, it } from "vitest";

import type { AnthropicMemoryTools } from "../src/ai-sdk/memory/index.ts";
import type { SyncedDatabaseLike } from "../src/powersync/index.ts";
import type { VercelConnectModule } from "../src/vercel-connect/index.ts";

/**
 * The structural types better-supabase declares instead of importing an
 * optional peer, checked against the peer's real types at the installed
 * version. A major release that breaks one fails here.
 */
describe("structurally typed optional peers", () => {
  it("@vercel/connect has the functions the credential provider calls", () => {
    expectTypeOf<typeof Connect>().toExtend<VercelConnectModule>();
  });

  it("@ai-sdk/anthropic has the pinned memory tool", () => {
    expectTypeOf<typeof anthropic.tools>().toExtend<AnthropicMemoryTools>();
  });

  it("a PowerSync database has what syncWithAuth drives", () => {
    expectTypeOf<CommonPowerSyncDatabase>().toExtend<
      SyncedDatabaseLike<PowerSyncBackendConnector>
    >();
  });
});
