"use client";

import type {
  UseCompletionHelpers,
  UseObjectHelpers,
  UseObjectOptions,
} from "@ai-sdk/react";
import type { FlexibleSchema, InferSchema, UseCompletionOptions } from "ai";

import { useCompletion, useObject } from "@ai-sdk/react";

export interface UseAssistantCompletionOptions extends Omit<
  UseCompletionOptions,
  "api" | "streamProtocol"
> {
  /** The route of `createCompletionRoute`. Defaults to `/api/completion`. */
  readonly api?: string;
  /** Custom throttle wait in ms for completion updates. */
  readonly throttle?: number;
}

/**
 * `useCompletion` wired to `createCompletionRoute`, which answers a plain text
 * stream.
 */
export function useAssistantCompletion(
  options: UseAssistantCompletionOptions = {},
): UseCompletionHelpers {
  return useCompletion({
    ...options,
    api: options.api ?? "/api/completion",
    streamProtocol: "text",
  });
}

export type UseAssistantObjectOptions<SCHEMA extends FlexibleSchema> = Omit<
  UseObjectOptions<SCHEMA, InferSchema<SCHEMA>>,
  "api"
> & {
  /** The route of `createObjectRoute`. Defaults to `/api/object`. */
  readonly api?: string;
};

/**
 * `useObject` wired to `createObjectRoute`: `submit(input)` posts the input and
 * `object` fills in as the JSON streams.
 */
export function useAssistantObject<
  SCHEMA extends FlexibleSchema,
  INPUT = unknown,
>(
  options: UseAssistantObjectOptions<SCHEMA>,
): UseObjectHelpers<InferSchema<SCHEMA>, INPUT> {
  return useObject<SCHEMA, InferSchema<SCHEMA>, INPUT>({
    ...options,
    api: options.api ?? "/api/object",
  });
}
