import { expectTypeOf, test } from "vitest";

import type { ImpersonationEvents } from "../../src/blocks/impersonation/events.ts";
import type {
  BlockEventSchema,
  BlockEventSchemas,
} from "../../src/spec/index.ts";

declare const wrong: BlockEventSchema<{ readonly adminId: number }>;

test("BlockEventSchemas checks schemas against a block's event map", () => {
  expectTypeOf<BlockEventSchemas<ImpersonationEvents>>().not.toBeAny();

  const checked: BlockEventSchemas<ImpersonationEvents> = {
    // @ts-expect-error: adminId is a string in SupportEventData
    "support_session.started": wrong,
  };

  const unknown: BlockEventSchemas<ImpersonationEvents> = {
    // @ts-expect-error: not a support event
    "nope.event": true,
  };

  expectTypeOf(checked).not.toBeAny();
  expectTypeOf(unknown).not.toBeAny();
});
