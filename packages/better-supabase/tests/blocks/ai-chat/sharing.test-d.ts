import { describe, expectTypeOf, it } from "vitest";

import type {
  AiChat,
  AiChatLink,
  AiChatParticipant,
  AiChatParty,
  AiChatShareSummary,
  AiChatVisibility,
} from "../../../src/blocks/ai-chat/index.ts";

describe("ai-chat sharing types", () => {
  it("has three visibilities", () => {
    expectTypeOf<AiChatVisibility>().toEqualTypeOf<
      "private" | "organization" | "shared"
    >();
  });

  it("names a party by its kind", () => {
    expectTypeOf<AiChatParty["kind"]>().toEqualTypeOf<
      "team" | "customer" | "external"
    >();
    expectTypeOf<Extract<AiChatParty, { kind: "team" }>>().toEqualTypeOf<{
      readonly kind: "team";
      readonly teamId: string;
    }>();
  });

  it("puts the owner in the participant list", () => {
    expectTypeOf<AiChatParticipant["role"]>().toEqualTypeOf<
      "owner" | "viewer" | "editor"
    >();
    expectTypeOf<AiChatParticipant["userId"]>().toEqualTypeOf<
      string | undefined
    >();
  });

  it("returns share summaries and links", () => {
    expectTypeOf<AiChat["chats"]["shareSummaries"]>()
      .parameter(0)
      .toEqualTypeOf<readonly string[]>();
    expectTypeOf<AiChatShareSummary["hasLink"]>().toEqualTypeOf<boolean>();
    expectTypeOf<AiChatLink["token"]>().toEqualTypeOf<string>();
  });
});

describe("ai-chat modes", () => {
  it("types a chat's mode as the union of options.modes", () => {
    type Typed = AiChat<Record<never, never>, "support" | "research">;

    expectTypeOf<
      Awaited<ReturnType<Typed["chats"]["get"]>> extends infer R
        ? R extends { ok: true; data: infer D }
          ? D extends { mode?: infer M }
            ? M
            : never
          : never
        : never
    >().toEqualTypeOf<"support" | "research" | undefined>();
  });
});
