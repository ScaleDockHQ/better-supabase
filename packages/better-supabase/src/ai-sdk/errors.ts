import type { DbError } from "../core/errors.ts";

import { isRecord } from "../core/block-helpers.ts";
import { dbError, dbErrorOf } from "../core/errors.ts";

const INVALID_INPUT: ReadonlySet<string> = new Set([
  "AI_InvalidArgumentError",
  "AI_InvalidPromptError",
  "AI_InvalidDataContentError",
  "AI_MessageConversionError",
  "AI_TooManyEmbeddingValuesForCallError",
]);

const PROVIDER_CONFIG: ReadonlySet<string> = new Set([
  "AI_LoadAPIKeyError",
  "AI_LoadSettingError",
]);

const GENERATION_FAILED: ReadonlySet<string> = new Set([
  "AI_NoObjectGeneratedError",
  "AI_NoContentGeneratedError",
  "AI_NoOutputGeneratedError",
  "AI_NoImageGeneratedError",
  "AI_NoSpeechGeneratedError",
  "AI_NoTranscriptGeneratedError",
  "AI_NoVideoGeneratedError",
  "AI_NoSuchToolError",
  "AI_InvalidToolInputError",
  "AI_ToolCallRepairError",
  "AI_JSONParseError",
  "AI_InvalidResponseDataError",
  "AI_EmptyResponseBodyError",
  "AI_UIMessageStreamError",
]);

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" && Number.isFinite(value) ? value : undefined;

function retryAfterOf(error: Record<string, unknown>): number | undefined {
  const headers = error["responseHeaders"];

  if (!isRecord(headers)) {
    return undefined;
  }

  const value = headers["retry-after"] ?? headers["Retry-After"];
  const seconds = typeof value === "string" ? Number(value) : Number.NaN;

  return Number.isFinite(seconds) && seconds >= 0
    ? Math.ceil(seconds)
    : undefined;
}

function ofStatus(
  status: number | undefined,
  error: Record<string, unknown>,
): DbError {
  if (status === 429) {
    const retryAfter = retryAfterOf(error);

    return dbError("rate_limited", "The model provider is rate limiting.", {
      code: "AI_PROVIDER_RATE_LIMITED",
      ...(retryAfter === undefined ? {} : { retryAfter }),
    });
  }

  if (status === 408 || status === 504) {
    return dbError("timeout", "The model provider timed out.", {
      code: "AI_PROVIDER_TIMEOUT",
    });
  }

  if (status === 400 || status === 413 || status === 422) {
    return dbError(
      "invalid_request",
      "The model provider refused the request.",
      { code: "AI_PROVIDER_BAD_REQUEST" },
    );
  }

  if (status === 404) {
    return dbError("not_found", "The model provider has no such resource.", {
      code: "AI_PROVIDER_NOT_FOUND",
    });
  }

  if (status === 401 || status === 403) {
    return dbError(
      "unexpected",
      "The model provider refused the credentials.",
      { code: "AI_PROVIDER_AUTH" },
    );
  }

  if (status !== undefined && status >= 500) {
    return dbError("network", "The model provider is unavailable.", {
      code: "AI_PROVIDER_UNAVAILABLE",
    });
  }

  return dbError("unexpected", "The model provider call failed.", {
    code: "AI_PROVIDER_FAILED",
  });
}

function ofGateway(type: string, error: Record<string, unknown>): DbError {
  switch (type) {
    case "rate_limit_exceeded": {
      return ofStatus(429, error);
    }

    case "timeout": {
      return ofStatus(504, error);
    }

    case "invalid_request_error": {
      return ofStatus(400, error);
    }

    case "model_not_found": {
      return dbError("not_found", "The AI Gateway has no such model.", {
        code: "AI_MODEL_NOT_FOUND",
      });
    }

    case "not_found": {
      return ofStatus(404, error);
    }

    case "forbidden": {
      return dbError("forbidden", "The AI Gateway refused the request.", {
        code: "AI_GATEWAY_FORBIDDEN",
      });
    }

    case "authentication_error": {
      return dbError("unexpected", "The AI Gateway refused the credentials.", {
        code: "AI_GATEWAY_AUTH",
      });
    }

    case "failed_dependency":
    case "internal_server_error": {
      return ofStatus(503, error);
    }

    default: {
      return ofStatus(numberOf(error["statusCode"]), error);
    }
  }
}

/**
 * An AI SDK or AI Gateway error as a `DbError`, so a route answers with the
 * same Problem Details as the rest of the app. Errors are matched by `name`
 * (and `type` for the gateway), so a second copy of `ai` still matches. The
 * message is fixed per kind; the provider's own message never reaches it, since
 * it can quote the prompt or a key.
 */
export function aiErrorToDbError(error: unknown): DbError {
  const known = dbErrorOf(error);

  if (known !== undefined) {
    return known;
  }

  if (!isRecord(error)) {
    return dbError("unexpected", "The generation failed.", {
      code: "AI_GENERATION_FAILED",
    });
  }

  const name = typeof error["name"] === "string" ? error["name"] : "";

  if (name === "AbortError" || name === "TimeoutError") {
    return name === "AbortError"
      ? dbError("aborted", "The generation was stopped.", {
          code: "AI_ABORTED",
        })
      : ofStatus(504, error);
  }

  if (name === "AI_RetryError") {
    const last = error["lastError"];

    return last === undefined || last === error
      ? ofStatus(undefined, error)
      : aiErrorToDbError(last);
  }

  if (name === "AI_APICallError") {
    return ofStatus(numberOf(error["statusCode"]), error);
  }

  if (name.startsWith("Gateway") && typeof error["type"] === "string") {
    return ofGateway(error["type"], error);
  }

  if (name === "AI_TypeValidationError") {
    return dbError("validation", "The value did not match its schema.", {
      code: "AI_TYPE_VALIDATION",
      issues: [{ message: "The value did not match its schema." }],
    });
  }

  if (name === "AI_NoSuchModelError" || name === "AI_NoSuchProviderError") {
    return dbError("not_found", "The model is not available.", {
      code: "AI_MODEL_NOT_FOUND",
    });
  }

  if (name === "AI_UnsupportedFunctionalityError") {
    return dbError("unsupported", "The model does not support this.", {
      code: "AI_UNSUPPORTED",
    });
  }

  if (name === "AI_DownloadError") {
    return dbError("network", "A file could not be downloaded.", {
      code: "AI_DOWNLOAD_FAILED",
    });
  }

  if (INVALID_INPUT.has(name)) {
    return dbError("invalid_request", "The request to the model is invalid.", {
      code: "AI_INVALID_REQUEST",
    });
  }

  if (PROVIDER_CONFIG.has(name)) {
    return dbError("unexpected", "The model provider is not configured.", {
      code: "AI_PROVIDER_CONFIG",
    });
  }

  return dbError("unexpected", "The generation failed.", {
    code: GENERATION_FAILED.has(name)
      ? "AI_GENERATION_FAILED"
      : "AI_UNEXPECTED",
  });
}

/**
 * The message a client sees for a stream error: the fixed message of
 * `aiErrorToDbError`. The default `onError` of `createAssistant`.
 */
export function aiErrorMessage(error: unknown): string {
  return aiErrorToDbError(error).message;
}
