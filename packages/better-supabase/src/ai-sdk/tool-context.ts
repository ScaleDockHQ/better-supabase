import type { StepResult, ToolSet } from "ai";

import type { StandardSchemaV1 } from "../core/standard.ts";

import { isRecord } from "../core/guards.ts";

/**
 * Who a tool call runs for: the tenant the tool must scope its work to. It is a
 * type alias because the SDK's `Context` has a string index signature, which an
 * interface doesn't satisfy.
 */
export type TenantToolContext = {
  readonly organizationId: string;
  readonly userId: string;
  readonly chatId?: string;
};

const text = (value: unknown): value is string =>
  typeof value === "string" && value !== "";

/**
 * The `contextSchema` of a tool that needs the tenant. The AI SDK validates the
 * context it hands to `execute` against it, so a missing organization fails the
 * call instead of running unscoped.
 */
export const tenantContextSchema: StandardSchemaV1<unknown, TenantToolContext> =
  {
    "~standard": {
      version: 1,
      vendor: "better-supabase",
      validate: (value) => {
        if (
          !isRecord(value) ||
          !text(value["organizationId"]) ||
          !text(value["userId"])
        ) {
          return {
            issues: [
              {
                message:
                  "Expected a tenant context with organizationId and userId.",
              },
            ],
          };
        }

        const { chatId } = value;

        return {
          value: {
            organizationId: value["organizationId"],
            userId: value["userId"],
            ...(text(chatId) ? { chatId } : {}),
          },
        };
      },
    },
  };

type ToolsContextOf<TOOLS extends ToolSet> = StepResult<TOOLS>["toolsContext"];

/**
 * The `toolsContext` for `generateText`, `streamText`, `ToolLoopAgent` and
 * `HarnessAgent.createSession`: one entry, the tenant, for every tool whose
 * `contextSchema` is `tenantContextSchema`. A tool with another schema gets no
 * entry here: spread its context over the result, as the SDK's types would ask
 * of a hand-written map.
 */
export function tenantToolsContext<TOOLS extends ToolSet>(
  tools: TOOLS,
  tenant: TenantToolContext,
): ToolsContextOf<TOOLS> {
  const entries: Record<string, TenantToolContext> = {};

  for (const [name, tool] of Object.entries(tools)) {
    if (tool.contextSchema === tenantContextSchema) {
      entries[name] = tenant;
    }
  }

  // SAFETY: every tool declaring `tenantContextSchema` gets an entry holding
  // the `TenantToolContext` that schema accepts. Tools with another schema are
  // the caller's to add, as documented.
  return entries as ToolsContextOf<TOOLS>;
}
