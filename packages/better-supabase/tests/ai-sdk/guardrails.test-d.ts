import type { LanguageModelMiddleware } from "ai";

import { describe, expectTypeOf, it } from "vitest";

import type { GuardrailsMiddlewareOptions } from "../../src/ai-sdk/guardrails.ts";
import type { AiGuardrails } from "../../src/blocks/ai-guardrails/index.ts";

import { guardrailsMiddleware } from "../../src/ai-sdk/guardrails.ts";

describe("guardrailsMiddleware", () => {
  it("returns an AI SDK language model middleware", () => {
    expectTypeOf(
      guardrailsMiddleware,
    ).returns.toEqualTypeOf<LanguageModelMiddleware>();
    expectTypeOf(guardrailsMiddleware)
      .parameter(0)
      .toEqualTypeOf<Pick<AiGuardrails, "check">>();
    expectTypeOf<GuardrailsMiddlewareOptions["agent"]>().toBeString();
    expectTypeOf<GuardrailsMiddlewareOptions["failOpen"]>().toEqualTypeOf<
      boolean | undefined
    >();
  });
});
