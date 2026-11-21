import type { HarnessAgent, HarnessAgentSession } from "@ai-sdk/harness/agent";

import { expectTypeOf, test } from "vitest";

import type {
  HarnessRouteAgent,
  HarnessRouteSession,
} from "../../../src/ai-sdk/agents/harness.ts";

test("a HarnessAgent and its session satisfy the route's structural types", () => {
  expectTypeOf<HarnessAgentSession>().toExtend<HarnessRouteSession>();
  expectTypeOf<HarnessAgent>().toExtend<
    HarnessRouteAgent<HarnessAgentSession>
  >();
});
