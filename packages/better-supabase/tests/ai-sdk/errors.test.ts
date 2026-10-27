import { APICallError, RetryError, TypeValidationError } from "ai";
import { describe, expect, it } from "vitest";

import { aiErrorMessage, aiErrorToDbError } from "../../src/ai-sdk/errors.ts";
import { dbError } from "../../src/core/errors.ts";

const apiCall = (
  statusCode: number | undefined,
  responseHeaders?: Record<string, string>,
) =>
  new APICallError({
    message: "secret prompt text",
    url: "https://provider.test",
    requestBodyValues: {},
    ...(statusCode === undefined ? {} : { statusCode }),
    ...(responseHeaders === undefined ? {} : { responseHeaders }),
  });

const named = (name: string, extra: Record<string, unknown> = {}) =>
  Object.assign(new Error("secret"), { name, ...extra });

const pick = (error: unknown) => {
  const mapped = aiErrorToDbError(error);

  return [mapped.kind, mapped.code];
};

describe("aiErrorToDbError", () => {
  it("maps provider call errors by status", () => {
    expect(aiErrorToDbError(apiCall(429, { "retry-after": "2.5" }))).toEqual(
      expect.objectContaining({
        kind: "rate_limited",
        code: "AI_PROVIDER_RATE_LIMITED",
        retryAfter: 3,
      }),
    );
    expect(
      aiErrorToDbError(apiCall(429, { "retry-after": "soon" })),
    ).not.toHaveProperty("retryAfter");
    expect(aiErrorToDbError(apiCall(429))).not.toHaveProperty("retryAfter");
    expect(pick(apiCall(408))).toEqual(["timeout", "AI_PROVIDER_TIMEOUT"]);
    expect(pick(apiCall(422))).toEqual([
      "invalid_request",
      "AI_PROVIDER_BAD_REQUEST",
    ]);
    expect(pick(apiCall(404))).toEqual(["not_found", "AI_PROVIDER_NOT_FOUND"]);
    expect(pick(apiCall(401))).toEqual(["unexpected", "AI_PROVIDER_AUTH"]);
    expect(pick(apiCall(502))).toEqual(["network", "AI_PROVIDER_UNAVAILABLE"]);
    expect(pick(apiCall(undefined))).toEqual([
      "unexpected",
      "AI_PROVIDER_FAILED",
    ]);
  });

  it("never quotes the provider's message", () => {
    expect(aiErrorMessage(apiCall(400))).not.toContain("secret");
    expect(aiErrorMessage(named("AI_NoObjectGeneratedError"))).toBe(
      "The generation failed.",
    );
  });

  it("unwraps retries to the last error", () => {
    const retry = new RetryError({
      message: "gave up",
      reason: "maxRetriesExceeded",
      errors: [apiCall(500), apiCall(429)],
    });

    expect(pick(retry)).toEqual(["rate_limited", "AI_PROVIDER_RATE_LIMITED"]);
    expect(pick(named("AI_RetryError"))).toEqual([
      "unexpected",
      "AI_PROVIDER_FAILED",
    ]);
  });

  it("maps AI Gateway errors by type", () => {
    const gateway = (type: string, statusCode?: number) =>
      named("GatewayError", { type, statusCode });

    expect(pick(gateway("rate_limit_exceeded"))).toEqual([
      "rate_limited",
      "AI_PROVIDER_RATE_LIMITED",
    ]);
    expect(pick(gateway("timeout"))).toEqual([
      "timeout",
      "AI_PROVIDER_TIMEOUT",
    ]);
    expect(pick(gateway("invalid_request_error"))).toEqual([
      "invalid_request",
      "AI_PROVIDER_BAD_REQUEST",
    ]);
    expect(pick(gateway("model_not_found"))).toEqual([
      "not_found",
      "AI_MODEL_NOT_FOUND",
    ]);
    expect(pick(gateway("not_found"))).toEqual([
      "not_found",
      "AI_PROVIDER_NOT_FOUND",
    ]);
    expect(pick(gateway("forbidden"))).toEqual([
      "forbidden",
      "AI_GATEWAY_FORBIDDEN",
    ]);
    expect(pick(gateway("authentication_error"))).toEqual([
      "unexpected",
      "AI_GATEWAY_AUTH",
    ]);
    expect(pick(gateway("failed_dependency"))).toEqual([
      "network",
      "AI_PROVIDER_UNAVAILABLE",
    ]);
    expect(pick(gateway("internal_server_error"))).toEqual([
      "network",
      "AI_PROVIDER_UNAVAILABLE",
    ]);
    expect(pick(gateway("response_error", 502))).toEqual([
      "network",
      "AI_PROVIDER_UNAVAILABLE",
    ]);
  });

  it("maps the other AI SDK errors by name", () => {
    expect(
      pick(new TypeValidationError({ value: 1, cause: new Error("x") })),
    ).toEqual(["validation", "AI_TYPE_VALIDATION"]);
    expect(pick(named("AI_NoSuchModelError"))).toEqual([
      "not_found",
      "AI_MODEL_NOT_FOUND",
    ]);
    expect(pick(named("AI_UnsupportedFunctionalityError"))).toEqual([
      "unsupported",
      "AI_UNSUPPORTED",
    ]);
    expect(pick(named("AI_DownloadError"))).toEqual([
      "network",
      "AI_DOWNLOAD_FAILED",
    ]);
    expect(pick(named("AI_InvalidPromptError"))).toEqual([
      "invalid_request",
      "AI_INVALID_REQUEST",
    ]);
    expect(pick(named("AI_LoadAPIKeyError"))).toEqual([
      "unexpected",
      "AI_PROVIDER_CONFIG",
    ]);
    expect(pick(named("AbortError"))).toEqual(["aborted", "AI_ABORTED"]);
    expect(pick(named("TimeoutError"))).toEqual([
      "timeout",
      "AI_PROVIDER_TIMEOUT",
    ]);
    expect(pick(named("Whatever"))).toEqual(["unexpected", "AI_UNEXPECTED"]);
    expect(pick({})).toEqual(["unexpected", "AI_UNEXPECTED"]);
    expect(pick("boom")).toEqual(["unexpected", "AI_GENERATION_FAILED"]);
  });

  it("passes DbErrors through", () => {
    const known = dbError("conflict", "Busy");

    expect(aiErrorToDbError(known)).toBe(known);
    expect(aiErrorToDbError(new Error("wrapped", { cause: known }))).toBe(
      known,
    );
  });
});
