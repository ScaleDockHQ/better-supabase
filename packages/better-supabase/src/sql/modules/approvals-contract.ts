import type { ModuleContractFunction } from "../context.ts";

/**
 * The approvals functions the module exposes; extra is the contract of
 * request_approval's `fields` argument.
 */
export function approvalsContract(
  extra: readonly string[],
): readonly ModuleContractFunction[] {
  return [
    {
      name: "request_approval",
      args: ["{id}", "text", "text", "text", "text", "jsonb", ...extra],
      returns: "jsonb",
    },
    {
      name: "decide_approval",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "delegate_approval",
      args: ["uuid", "uuid", "text"],
      returns: "jsonb",
    },
    { name: "cancel_approval", args: ["uuid"], returns: "jsonb" },
    { name: "is_approved", args: ["text", "text", "text"], returns: "boolean" },
  ];
}
