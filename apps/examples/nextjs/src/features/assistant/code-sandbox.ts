import type { Experimental_SandboxSession, ToolSet } from "ai";
import type { AiSandboxes } from "better-supabase/blocks/ai-chat";
import type { VercelSandboxes } from "better-supabase/vercel-sandbox";

import "server-only";
import { codeTool } from "better-supabase/ai-sdk";
import { untrusted, vercelSandboxes } from "better-supabase/vercel-sandbox";

import { env } from "@/env";

/** The `streamText` options that let an answer run code. */
export interface CodeOptions {
  readonly tools: ToolSet;
  readonly experimental_sandbox?: Experimental_SandboxSession;
}

/** An answer without a sandbox: no `runCode` tool. */
export const NO_CODE: CodeOptions = { tools: {} };

let vercelInstance: VercelSandboxes | undefined;

/** One adapter per process, over the chat block's service-role sandboxes. */
function vercel(sandboxes: AiSandboxes): VercelSandboxes {
  vercelInstance ??= vercelSandboxes({ sandboxes, defaults: untrusted });

  return vercelInstance;
}

/**
 * The chat's Vercel sandbox and the `runCode` tool when `ASSISTANT_SANDBOX` is
 * `vercel`. Each run waits for the user's approval in the chat (`toolApproval`
 * in the model call).
 */
export async function codeSandbox(
  sandboxes: AiSandboxes,
  organizationId: string,
  chatId: string,
  options: { readonly userId: string; readonly signal: AbortSignal },
): Promise<CodeOptions> {
  if (env.ASSISTANT_SANDBOX !== "vercel") {
    return NO_CODE;
  }

  const { session } = await vercel(sandboxes)
    .forChat(organizationId, chatId, {
      userId: options.userId,
      signal: options.signal,
    })
    .orThrow();

  return {
    tools: { runCode: codeTool({ languages: ["python", "node"] }) },
    experimental_sandbox: session,
  };
}
