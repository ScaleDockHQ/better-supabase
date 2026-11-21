import type { LanguageModelMiddleware, ToolSet } from "ai";

import type {
  AiGuardrails,
  GuardrailStage,
  GuardrailVerdict,
  GuardTextOptions,
} from "../blocks/ai-guardrails/ai-guardrails.ts";

type WrapGenerate = NonNullable<LanguageModelMiddleware["wrapGenerate"]>;

type WrapStream = NonNullable<LanguageModelMiddleware["wrapStream"]>;

type Call = Parameters<WrapGenerate>[0];

type Params = Call["params"];

type Prompt = Params["prompt"];

type GenerateResult = Awaited<ReturnType<WrapGenerate>>;

type StreamResult = Awaited<ReturnType<WrapStream>>;

type StreamPart =
  StreamResult["stream"] extends ReadableStream<infer P> ? P : never;

/** What `guardrailsMiddleware` takes: the options of `guardText`. */
export type GuardrailsMiddlewareOptions = GuardTextOptions;

const DEFAULT_REFUSAL = "This request can't be processed.";

const ZERO_USAGE: GenerateResult["usage"] = {
  inputTokens: { total: 0, noCache: 0, cacheRead: 0, cacheWrite: 0 },
  outputTokens: { total: 0, text: 0, reasoning: 0 },
};

const STOP = { unified: "stop", raw: undefined } as const;

function lastUserIndex(prompt: Prompt): number {
  for (let index = prompt.length - 1; index >= 0; index -= 1) {
    if (prompt[index]?.role === "user") {
      return index;
    }
  }

  return -1;
}

function textOfUser(prompt: Prompt, index: number): string {
  const message = prompt[index];

  return message?.role === "user"
    ? message.content
        .flatMap((part) => (part.type === "text" ? [part.text] : []))
        .join("\n")
    : "";
}

type UserContent = Extract<Prompt[number], { role: "user" }>["content"];

/** Replaces the user message's text parts with one part holding `text`. */
function withUserText(prompt: Prompt, index: number, text: string): Prompt {
  return prompt.map((message, at) => {
    if (at !== index || message.role !== "user") {
      return message;
    }

    const content: UserContent = [];
    let placed = false;

    for (const part of message.content) {
      if (part.type !== "text") {
        content.push(part);
      } else if (!placed) {
        placed = true;
        content.push({ ...part, text });
      }
    }

    return { ...message, content };
  });
}

/**
 * A language model middleware that runs the ai-guardrails policy around a model
 * call. The last user message is checked before the model runs: a `block`
 * returns the refusal without calling the model and a `redact` rewrites the
 * prompt. The answer is checked afterwards, and a streamed text block is held
 * until its `text-end`, then emitted redacted or replaced by the refusal. Each
 * check logs one decision.
 *
 * A check that cannot run blocks the stage unless `failOpen` is set.
 */
export function guardrailsMiddleware(
  guardrails: Pick<AiGuardrails, "check">,
  options: GuardrailsMiddlewareOptions,
): LanguageModelMiddleware {
  const refusal = options.refusal ?? DEFAULT_REFUSAL;

  const run = async (
    stage: GuardrailStage,
    text: string,
    toolDepth: number,
  ): Promise<GuardrailVerdict> => {
    const checked = await guardrails.check({
      agent: options.agent,
      stage,
      text,
      toolDepth,
      ...(options.organizationId
        ? { organizationId: options.organizationId }
        : {}),
      ...(options.chatId ? { chatId: options.chatId } : {}),
    });

    if (checked.ok) {
      return checked.data;
    }

    return {
      decision: options.failOpen ? "allow" : "block",
      text,
      reasons: options.failOpen
        ? []
        : [
            {
              code: "injection",
              detail: "guardrail_unavailable",
              blocking: true,
            },
          ],
      logged: undefined,
    };
  };

  /** The prompt to send, or `undefined` when the input is blocked. */
  const checkInput = async (params: Params): Promise<Params | undefined> => {
    const index = lastUserIndex(params.prompt);
    const text = textOfUser(params.prompt, index);

    if (text.trim() === "") {
      return params;
    }

    const toolDepth = params.prompt.filter(
      (message) => message.role === "tool",
    ).length;

    const verdict = await run("input", text, toolDepth);

    if (verdict.decision === "block") {
      return undefined;
    }

    return verdict.decision === "redact"
      ? { ...params, prompt: withUserText(params.prompt, index, verdict.text) }
      : params;
  };

  const toolDepthOf = (params: Params): number =>
    params.prompt.filter((message) => message.role === "tool").length;

  /** The text to show for a model answer. */
  const checkOutput = async (params: Params, text: string): Promise<string> => {
    if (text.trim() === "") {
      return text;
    }

    const verdict = await run("output", text, toolDepthOf(params));

    return verdict.decision === "block" ? refusal : verdict.text;
  };

  const refused = (): GenerateResult => ({
    content: [{ type: "text", text: refusal }],
    finishReason: STOP,
    usage: ZERO_USAGE,
    warnings: [],
  });

  return {
    wrapGenerate: async ({ model, params }) => {
      const allowed = await checkInput(params);

      if (allowed === undefined) {
        return refused();
      }

      const result = await model.doGenerate(allowed);

      const content = await Promise.all(
        result.content.map(async (part) => {
          if (part.type !== "text") {
            return part;
          }

          return { ...part, text: await checkOutput(allowed, part.text) };
        }),
      );

      return { ...result, content };
    },

    wrapStream: async ({ model, params }) => {
      const allowed = await checkInput(params);

      if (allowed === undefined) {
        const stream = new ReadableStream<StreamPart>({
          start(controller) {
            controller.enqueue({ type: "stream-start", warnings: [] });
            controller.enqueue({ type: "text-start", id: "refusal" });
            controller.enqueue({
              type: "text-delta",
              id: "refusal",
              delta: refusal,
            });
            controller.enqueue({ type: "text-end", id: "refusal" });
            controller.enqueue({
              type: "finish",
              finishReason: STOP,
              usage: ZERO_USAGE,
            });
            controller.close();
          },
        });

        return { stream };
      }

      const result = await model.doStream(allowed);
      const held = new Map<string, { start: StreamPart; text: string }>();

      const stream = result.stream.pipeThrough(
        new TransformStream<StreamPart, StreamPart>({
          async transform(part, controller) {
            if (part.type === "text-start") {
              held.set(part.id, { start: part, text: "" });

              return;
            }

            if (part.type === "text-delta") {
              const block = held.get(part.id);

              if (block) {
                block.text += part.delta;

                return;
              }
            }

            if (part.type === "text-end") {
              const block = held.get(part.id);

              if (block) {
                held.delete(part.id);

                const text = await checkOutput(allowed, block.text);

                controller.enqueue(block.start);

                if (text !== "") {
                  controller.enqueue({
                    type: "text-delta",
                    id: part.id,
                    delta: text,
                  });
                }

                controller.enqueue(part);

                return;
              }
            }

            controller.enqueue(part);
          },
        }),
      );

      return { ...result, stream };
    },
  };
}

/** What `guardTools` takes: the options of `guardText`. */
export type GuardToolsOptions = GuardTextOptions;

const isIterable = (value: unknown): value is AsyncIterable<unknown> =>
  typeof value === "object" && value !== null && Symbol.asyncIterator in value;

const jsonOf = (value: unknown): string =>
  typeof value === "string" ? value : JSON.stringify(value);

/** The redacted text as the value it replaces: a string stays one. */
function valueOf(original: unknown, redacted: string): unknown {
  if (typeof original === "string") {
    return redacted;
  }

  try {
    return JSON.parse(redacted);
  } catch {
    return redacted;
  }
}

/**
 * Wraps each tool's `execute` so the ai-guardrails policy runs on what the
 * model sends and on what the tool returns. The input is checked as JSON at the
 * `input` stage, with the number of tool calls so far as `toolDepth`. A `block`
 * skips the tool and returns the refusal as its output, a `redact` runs it on
 * the rewritten input. The output is checked at the `output` stage the same
 * way, so injected instructions in a web page or a document the tool fetched
 * never reach the model as they came. A tool without `execute` is left alone.
 *
 * A check that cannot run blocks the stage unless `failOpen` is set.
 */
export function guardTools<TOOLS extends ToolSet>(
  tools: TOOLS,
  guardrails: Pick<AiGuardrails, "check">,
  options: GuardToolsOptions,
): TOOLS {
  const refusal = options.refusal ?? DEFAULT_REFUSAL;
  let depth = 0;

  const run = async (
    stage: GuardrailStage,
    text: string,
    toolDepth: number,
  ): Promise<GuardrailVerdict> => {
    const checked = await guardrails.check({
      agent: options.agent,
      stage,
      text,
      toolDepth,
      ...(options.organizationId
        ? { organizationId: options.organizationId }
        : {}),
      ...(options.chatId ? { chatId: options.chatId } : {}),
    });

    if (checked.ok) {
      return checked.data;
    }

    return {
      decision: options.failOpen ? "allow" : "block",
      text,
      reasons: [],
      logged: undefined,
    };
  };

  const guardOutput = async (value: unknown, toolDepth: number) => {
    const text = jsonOf(value);

    if (text === "") {
      return value;
    }

    const verdict = await run("output", text, toolDepth);

    if (verdict.decision === "block") {
      return refusal;
    }

    return verdict.decision === "redact" ? valueOf(value, verdict.text) : value;
  };

  const entries = Object.entries(tools).map(([name, tool]) => {
    const { execute } = tool;

    if (execute === undefined) {
      return [name, tool] as const;
    }

    const guarded = {
      ...tool,
      execute: async (input: unknown, context: unknown) => {
        depth += 1;
        const toolDepth = depth;
        const checked = await run("input", jsonOf(input), toolDepth);

        if (checked.decision === "block") {
          return refusal;
        }

        const next =
          checked.decision === "redact" ? valueOf(input, checked.text) : input;

        // SAFETY: `execute` is the tool's own function; the SDK calls the
        // wrapper with the arguments it would pass to it.
        const result: unknown = await (
          execute as (input: unknown, context: unknown) => unknown
        )(next, context);

        if (!isIterable(result)) {
          return guardOutput(result, toolDepth);
        }

        return (async function* guardedStream() {
          for await (const chunk of result) {
            yield await guardOutput(chunk, toolDepth);
          }
        })();
      },
    };

    return [name, guarded] as const;
  });

  // SAFETY: each entry keeps its tool's name and shape; only `execute` is
  // wrapped, and its input and output types are the tool's own.
  return Object.fromEntries(entries) as TOOLS;
}
