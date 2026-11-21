import type { MCPClient } from "@ai-sdk/mcp";
import type { ModelMessage, ToolSet } from "ai";

import { jsonSchema, tool } from "ai";

import { errorText } from "../../core/block-helpers.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";

/**
 * The MCP client methods for resources and prompts, as `connectTools` returns
 * them.
 */
export type McpResourceClient = Pick<
  MCPClient,
  "getPrompt" | "listPrompts" | "listResources" | "readResource"
>;

export interface McpResourceToolsOptions {
  /** Prefixes the tool names, such as `github_`, like `connectTools`' `prefix`. */
  readonly prefix?: string;
  /**
   * The most characters one `read` returns. Longer text is cut and marked
   * `truncated`. Default 50 000.
   */
  readonly maxChars?: number;
  /**
   * Decides whether a URI may be read. By default only a URI the server listed
   * in `resources/list` can be read, so the model can't ask for an address the
   * server never offered.
   */
  readonly allow?: (uri: string) => boolean | Promise<boolean>;
}

interface ResourceSummary {
  readonly uri: string;
  readonly name: string;
  readonly description?: string;
  readonly mimeType?: string;
}

const EMPTY_OBJECT = jsonSchema<Record<string, never>>({
  type: "object",
  properties: {},
  additionalProperties: false,
});

const URI_INPUT = jsonSchema<{ uri: string }>({
  type: "object",
  properties: { uri: { type: "string" } },
  required: ["uri"],
  additionalProperties: false,
});

/**
 * Two read-only tools over an MCP server's resources, `list_resources` and
 * `read_resource`, so a model can read what the server exposes (a schema, a
 * document, a log) without the app hard-coding each one. A binary resource is
 * reported by its type and size, never inlined.
 */
export function mcpResourceTools(
  client: Pick<McpResourceClient, "listResources" | "readResource">,
  options: McpResourceToolsOptions = {},
): ToolSet {
  const prefix = options.prefix ?? "";
  const maxChars = options.maxChars ?? 50_000;

  const list = async (): Promise<readonly ResourceSummary[]> => {
    const summaries: ResourceSummary[] = [];
    let cursor: string | undefined;

    do {
      const page = await client.listResources(
        cursor === undefined ? {} : { params: { cursor } },
      );

      for (const resource of page.resources) {
        summaries.push({
          uri: resource.uri,
          name: resource.name,
          ...(resource.description === undefined
            ? {}
            : { description: resource.description }),
          ...(resource.mimeType === undefined
            ? {}
            : { mimeType: resource.mimeType }),
        });
      }

      cursor = page.nextCursor;
    } while (cursor !== undefined);

    return summaries;
  };

  const allowed = async (uri: string): Promise<boolean> =>
    options.allow
      ? options.allow(uri)
      : (await list()).some((resource) => resource.uri === uri);

  return {
    [`${prefix}list_resources`]: tool({
      description: "Lists the resources this server exposes.",
      inputSchema: EMPTY_OBJECT,
      execute: async () => ({ resources: await list() }),
    }),
    [`${prefix}read_resource`]: tool({
      description: "Reads one resource by the URI `list_resources` returned.",
      inputSchema: URI_INPUT,
      execute: async ({ uri }) => {
        if (!(await allowed(uri))) {
          return { error: "This resource is not offered by the server." };
        }

        const result = await client.readResource({ uri });

        return {
          contents: result.contents.map((content) => {
            if ("text" in content && typeof content.text === "string") {
              const { text } = content;
              const truncated = text.length > maxChars;

              return {
                uri: content.uri,
                ...(content.mimeType === undefined
                  ? {}
                  : { mimeType: content.mimeType }),
                text: truncated ? text.slice(0, maxChars) : text,
                truncated,
              };
            }

            const blob = "blob" in content ? String(content.blob) : "";

            return {
              uri: content.uri,
              ...(content.mimeType === undefined
                ? {}
                : { mimeType: content.mimeType }),
              binary: true,
              bytes: Math.floor((blob.length * 3) / 4),
            };
          }),
        };
      },
    }),
  };
}

/** One prompt a server offers. */
export interface McpPromptSummary {
  readonly name: string;
  readonly description?: string;
  readonly arguments: readonly {
    readonly name: string;
    readonly description?: string;
    readonly required: boolean;
  }[];
}

/** Lists the prompts an MCP server offers. */
export function mcpPrompts(
  client: Pick<McpResourceClient, "listPrompts">,
): AsyncResult<readonly McpPromptSummary[]> {
  return AsyncResult.from(async () => {
    try {
      const summaries: McpPromptSummary[] = [];
      let cursor: string | undefined;

      do {
        const page = await client.listPrompts(
          cursor === undefined ? {} : { params: { cursor } },
        );

        for (const prompt of page.prompts) {
          summaries.push({
            name: prompt.name,
            ...(prompt.description === undefined
              ? {}
              : { description: prompt.description }),
            arguments: (prompt.arguments ?? []).map((argument) => ({
              name: argument.name,
              ...(argument.description === undefined
                ? {}
                : { description: argument.description }),
              required: argument.required === true,
            })),
          });
        }

        cursor = page.nextCursor;
      } while (cursor !== undefined);

      return ok(summaries);
    } catch (error) {
      return err(dbError("network", errorText(error)));
    }
  });
}

type Part = Extract<ModelMessage, { role: "user" }>["content"] extends
  | string
  | (infer P)[]
  ? P
  : never;

type PromptContent = Awaited<
  ReturnType<McpResourceClient["getPrompt"]>
>["messages"][number]["content"];

/** A prompt content block as model message parts; non-text becomes a note. */
function partsOf(content: PromptContent, role: string): Part[] {
  switch (content.type) {
    case "text": {
      return [{ type: "text", text: content.text }];
    }

    case "image": {
      return role === "user"
        ? [{ type: "image", image: content.data, mediaType: content.mimeType }]
        : [{ type: "text", text: `[image ${content.mimeType}]` }];
    }

    case "resource": {
      return [
        {
          type: "text",
          text:
            "text" in content.resource &&
            typeof content.resource.text === "string"
              ? content.resource.text
              : `[binary resource ${content.resource.uri}]`,
        },
      ];
    }

    case "resource_link": {
      return [{ type: "text", text: `[resource ${content.uri}]` }];
    }

    default: {
      const unreachable: never = content;

      return unreachable;
    }
  }
}

/**
 * Fetches a server prompt and returns it as model messages to prepend to a
 * conversation. Image blocks go to `user` messages only; elsewhere they become
 * a short note.
 */
export function mcpPromptMessages(
  client: Pick<McpResourceClient, "getPrompt">,
  name: string,
  args?: Record<string, string>,
): AsyncResult<readonly ModelMessage[]> {
  return AsyncResult.from(async () => {
    try {
      const prompt = await client.getPrompt({
        name,
        ...(args === undefined ? {} : { arguments: args }),
      });

      const messages: ModelMessage[] = prompt.messages.map((message) => {
        const parts = partsOf(message.content, message.role);

        if (message.role === "user") {
          return { role: "user", content: parts };
        }

        return {
          role: "assistant",
          content: parts.flatMap((part) =>
            part.type === "text"
              ? [{ type: "text" as const, text: part.text }]
              : [],
          ),
        };
      });

      return ok(messages);
    } catch (error) {
      return err(dbError("network", errorText(error)));
    }
  });
}
