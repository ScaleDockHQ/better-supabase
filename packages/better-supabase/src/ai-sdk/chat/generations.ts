import type { LanguageModelUsage } from "ai";

import { createTextStreamResponse } from "ai";

import type { DbError } from "../../core/errors.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { GatewayOptions } from "../gateway-options.ts";
import type { AiUsage } from "../gateway.ts";

import { isRecord } from "../../core/block-helpers.ts";
import { problemResponse } from "../../core/problem.ts";
import { validate } from "../../core/standard.ts";
import { aiErrorToDbError } from "../errors.ts";
import { gatewayOptions, problem429, usageOf } from "../gateway.ts";
import { badRequest, readJson } from "../http.ts";

/** Who asks, for one generation request. */
export interface GenerationContext {
  readonly userId: string;
  readonly organizationId: string;
  /** Keeps the function alive until `onFinish` ran: `after` in Next.js. */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

/** What `run` gets to start one generation. */
export interface GenerationRunArgs<INPUT> {
  /** The prompt of `useCompletion`, or the value `useObject` submitted. */
  readonly input: INPUT;
  /** The request body as sent, for extra fields. */
  readonly body: Readonly<Record<string, unknown>>;
  readonly model: string;
  /** Aborted when the client goes away; pass it to `streamText`. */
  readonly abortSignal: AbortSignal;
  readonly providerOptions: { readonly gateway: GatewayOptions };
  readonly context: GenerationContext;
}

/**
 * The part of a `streamText` result a generation route reads. For `useObject`,
 * run `streamText` with `output: Output.object({ schema })`; its `textStream`
 * is the JSON the hook parses.
 */
export interface GenerationRunResult {
  readonly textStream: ReadableStream<string>;
  readonly usage?: PromiseLike<LanguageModelUsage>;
  readonly finalStep?: PromiseLike<{ readonly providerMetadata?: unknown }>;
}

/** What `onFinish` gets once the stream ended. */
export interface GenerationFinish<INPUT> {
  readonly input: INPUT;
  /** The streamed text: the completion, or the object's JSON. */
  readonly text: string;
  readonly model: string;
  readonly usage: AiUsage;
  readonly context: GenerationContext;
}

export interface GenerationRouteOptions<INPUT> {
  readonly run: (
    args: GenerationRunArgs<INPUT>,
  ) => GenerationRunResult | PromiseLike<GenerationRunResult>;
  readonly model: string;
  /** The quota check before a generation; an error answers 429. */
  readonly quota?: (organizationId: string) => Promise<DbError | undefined>;
  /** The `feature` tag of the gateway options. */
  readonly feature?: string;
  /** Called after the stream ended, such as to meter the usage. */
  readonly onFinish?: (finish: GenerationFinish<INPUT>) => void | Promise<void>;
}

export interface GenerationRoute {
  respond(request: Request, context: GenerationContext): Promise<Response>;
}

const settle = async <T>(
  value: PromiseLike<T> | undefined,
): Promise<T | undefined> => {
  try {
    return await value;
  } catch {
    return undefined;
  }
};

type Parsed<INPUT> =
  | { readonly ok: true; readonly input: INPUT }
  | { readonly ok: false; readonly response: Response };

function generationRoute<INPUT>(
  options: GenerationRouteOptions<INPUT>,
  inputOf: (
    body: Readonly<Record<string, unknown>>,
  ) => Parsed<INPUT> | Promise<Parsed<INPUT>>,
  defaultFeature: string,
): GenerationRoute {
  return {
    async respond(request, context) {
      const body = await readJson(request);

      if (!isRecord(body)) {
        return badRequest("Expected a JSON object.");
      }

      const parsed = await inputOf(body);

      if (!parsed.ok) {
        return parsed.response;
      }

      const { input } = parsed;

      if (options.quota) {
        const exceeded = await options.quota(context.organizationId);

        if (exceeded) {
          return problem429(exceeded);
        }
      }

      const abort = new AbortController();

      request.signal.addEventListener("abort", () => {
        abort.abort();
      });

      let result: GenerationRunResult;

      try {
        result = await options.run({
          input,
          body,
          model: options.model,
          abortSignal: abort.signal,
          providerOptions: gatewayOptions({
            userId: context.userId,
            organizationId: context.organizationId,
            feature: options.feature ?? defaultFeature,
          }),
          context,
        });
      } catch (cause) {
        return problemResponse(aiErrorToDbError(cause));
      }

      let text = "";
      const { promise: done, resolve: ended } = Promise.withResolvers<void>();

      const textStream = result.textStream.pipeThrough(
        new TransformStream<string, string>({
          transform(chunk, controller) {
            text += chunk;
            controller.enqueue(chunk);
          },
          flush() {
            ended();
          },
        }),
      );

      if (options.onFinish !== undefined) {
        const onFinish = options.onFinish;

        context.waitUntil?.(
          (async () => {
            await done;

            await onFinish({
              input,
              text,
              model: options.model,
              usage: usageOf({
                usage: await settle(result.usage),
                finalStep: await settle(result.finalStep),
              }),
              context,
            });
          })(),
        );
      }

      return createTextStreamResponse({ stream: textStream });
    },
  };
}

/**
 * A route for `useCompletion` (or `useAssistantCompletion`): reads `prompt`,
 * checks the quota, tags the gateway call with the user and tenant, streams the
 * text and calls `onFinish` with the usage after the stream ended.
 */
export function createCompletionRoute(
  options: GenerationRouteOptions<string>,
): GenerationRoute {
  return generationRoute(
    options,
    (body) => {
      const prompt = body["prompt"];

      return typeof prompt === "string" && prompt.trim() !== ""
        ? { ok: true, input: prompt }
        : { ok: false, response: badRequest("Expected a prompt.") };
    },
    "completion",
  );
}

/**
 * A route for `useObject` (or `useAssistantObject`): the body is the value
 * `submit` sent, checked against `input` when given (a failure answers 422),
 * and `run` streams the object's JSON text. The quota, the gateway tags and
 * `onFinish` work as in `createCompletionRoute`.
 */
export function createObjectRoute<
  SCHEMA extends StandardSchemaV1 = StandardSchemaV1,
>(
  options: GenerationRouteOptions<StandardSchemaV1.InferOutput<SCHEMA>> & {
    readonly input?: SCHEMA;
  },
): GenerationRoute {
  return generationRoute(
    options,
    async (body) => {
      if (options.input === undefined) {
        return { ok: true, input: body };
      }

      const result = await validate(options.input, body, "input");

      return result.ok
        ? { ok: true, input: result.data }
        : { ok: false, response: problemResponse(result.error) };
    },
    "object",
  );
}
