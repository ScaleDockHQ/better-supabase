import type { McpTool } from "../mcp/index.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";

import { defineTool } from "../mcp/index.ts";

/** The WebMCP tool name rule: 1 to 128 ASCII letters, digits, `_`, `-` or `.`. */
const TOOL_NAME = /^[A-Za-z0-9_.-]{1,128}$/;

/** A `Result` of a block repository method, typed structurally. */
export interface ActionResult<T> {
  readonly ok: boolean;
  readonly data: T | null;
  readonly error: { readonly message: string } | null;
}

/**
 * One block repository method offered to agents: the same definition feeds the
 * browser (`registerWebMcpTools`) and a server (`mcpToolsOf`).
 */
export interface BlockAction<I = Record<string, unknown>> {
  /** Unique in a document; WebMCP and MCP both bound its length and characters. */
  readonly name: string;
  readonly title?: string;
  /** What the tool does, in words an agent can pick it by. */
  readonly description: string;
  /** A JSON Schema object; put a `description` on each property. */
  readonly inputSchema: Readonly<Record<string, unknown>>;
  /**
   * The permission the caller needs. `null` is an explicit decision that the
   * action needs none; leaving it out is a type error so no action is public by
   * accident.
   */
  readonly permission: string | null;
  /** The action only reads. Sets `readOnlyHint`. */
  readonly readOnly?: boolean;
  /** The action buys, sends, deletes or otherwise can't be taken back. */
  readonly consequential?: boolean;
  /** The result carries user-written or external text. */
  readonly untrustedContent?: boolean;
  run(input: I, options: { readonly signal: AbortSignal }): Promise<unknown>;
}

/**
 * Wraps a repository method as an action: its `Result` becomes the action's
 * value, and an error becomes a rejection with the database error's message.
 */
export function blockAction<I extends object, T>(
  definition: Omit<BlockAction<I>, "run"> & {
    readonly call: (input: I) => PromiseLike<ActionResult<T>>;
  },
): BlockAction<I> {
  const { call, ...rest } = definition;

  return {
    ...rest,
    async run(input) {
      const result = await call(input);

      if (!result.ok) {
        throw new Error(result.error?.message ?? "The action failed");
      }

      return result.data;
    },
  };
}

/** `document.modelContext` as the WebMCP draft defines it, typed structurally. */
export interface ModelContextLike {
  registerTool(
    tool: {
      readonly name: string;
      readonly title?: string;
      readonly description: string;
      readonly inputSchema: Readonly<Record<string, unknown>>;
      readonly annotations?: {
        readonly readOnlyHint?: boolean;
        readonly untrustedContentHint?: boolean;
        readonly consequentialHint?: boolean;
      };
      execute(
        input: Record<string, unknown>,
        client?: unknown,
      ): Promise<unknown>;
    },
    options?: { readonly signal?: AbortSignal },
  ): unknown;
}

export interface WebMcpOptions {
  /**
   * Whether the signed-in user holds the permission. Actions whose permission
   * this denies are not registered, and the check runs again on every call.
   */
  can(permission: string): boolean | Promise<boolean>;
  /**
   * The model context; defaults to `document.modelContext`, then the legacy
   * `navigator.modelContext`. Without either, nothing registers.
   */
  readonly modelContext?: ModelContextLike;
  /** Unregisters every tool when aborted. */
  readonly signal?: AbortSignal;
}

export interface WebMcpRegistration {
  readonly registered: readonly string[];
  /** Actions left out, with the reason. */
  readonly skipped: readonly {
    readonly name: string;
    readonly reason: "denied" | "invalid-name" | "no-model-context";
  }[];
  /** Unregisters the tools this call registered. */
  unregister(): void;
}

function isModelContext(value: unknown): value is ModelContextLike {
  return (
    typeof value === "object" &&
    value !== null &&
    "registerTool" in value &&
    typeof value.registerTool === "function"
  );
}

/** The page's model context, read only through guarded property access. */
function pageModelContext(): ModelContextLike | undefined {
  const scope: unknown = globalThis;

  if (typeof scope !== "object" || scope === null) {
    return undefined;
  }

  const document: unknown = "document" in scope ? scope.document : undefined;

  const current =
    typeof document === "object" &&
    document !== null &&
    "modelContext" in document
      ? document.modelContext
      : undefined;

  if (isModelContext(current)) {
    return current;
  }

  const navigator: unknown = "navigator" in scope ? scope.navigator : undefined;

  const legacy =
    typeof navigator === "object" &&
    navigator !== null &&
    "modelContext" in navigator
      ? navigator.modelContext
      : undefined;

  return isModelContext(legacy) ? legacy : undefined;
}

/**
 * Registers the actions the user may run as WebMCP tools. The browser's agent
 * sees only those tools, and each call checks the permission again, so a
 * permission revoked after registration still stops the call.
 */
export async function registerWebMcpTools(
  actions: readonly BlockAction[],
  options: WebMcpOptions,
): Promise<WebMcpRegistration> {
  const context = options.modelContext ?? pageModelContext();
  const controller = new AbortController();
  const registered: string[] = [];

  const skipped: {
    name: string;
    reason: "denied" | "invalid-name" | "no-model-context";
  }[] = [];

  options.signal?.addEventListener("abort", () => {
    controller.abort();
  });

  for (const action of actions) {
    if (context === undefined) {
      skipped.push({ name: action.name, reason: "no-model-context" });
      continue;
    }

    if (!TOOL_NAME.test(action.name)) {
      skipped.push({ name: action.name, reason: "invalid-name" });
      continue;
    }

    if (action.permission !== null && !(await options.can(action.permission))) {
      skipped.push({ name: action.name, reason: "denied" });
      continue;
    }

    const { permission } = action;

    await context.registerTool(
      {
        name: action.name,
        ...(action.title === undefined ? {} : { title: action.title }),
        description: action.description,
        inputSchema: action.inputSchema,
        annotations: {
          readOnlyHint: action.readOnly === true,
          untrustedContentHint: action.untrustedContent === true,
          consequentialHint: action.consequential === true,
        },
        async execute(input) {
          if (permission !== null && !(await options.can(permission))) {
            throw new Error(
              `You need the permission ${permission} for this action`,
            );
          }

          return action.run(input, { signal: controller.signal });
        },
      },
      { signal: controller.signal },
    );

    registered.push(action.name);
  }

  return {
    registered,
    skipped,
    unregister() {
      controller.abort();
    },
  };
}

/**
 * The same actions as MCP tools for `createMcp({ tools })`. Each tool's
 * `permission` goes to the server's authorizer, so tools/list hides what the
 * caller may not run.
 */
export function mcpToolsOf<
  M extends AnyModels = AnyModels,
  F extends AnyFunctions = AnyFunctions,
  E = unknown,
>(actions: readonly BlockAction[]): readonly McpTool<M, F, E>[] {
  return actions.map((action) =>
    defineTool<M, F, E>({
      name: action.name,
      ...(action.title === undefined ? {} : { title: action.title }),
      description: action.description,
      inputSchema: {
        // SAFETY: the action's schema is JSON by contract.
        ...(action.inputSchema as Record<string, never>),
      },
      annotations: {
        readOnlyHint: action.readOnly === true,
        destructiveHint: action.consequential === true,
        openWorldHint: action.untrustedContent === true,
      },
      ...(action.permission === null ? {} : { permission: action.permission }),
      run: (input, ctx) => action.run(input, { signal: ctx.signal }),
    }),
  );
}
