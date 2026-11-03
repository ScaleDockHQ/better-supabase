import type { LanguageModelMiddleware } from "ai";

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
