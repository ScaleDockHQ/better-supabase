import type { ResolvedConfig } from "../../config/index.ts";

/**
 * Warnings for config the next minor turns into a failure, one line each.
 * `blocks.audit.options.exempt` entries written as a bare glob give no reason,
 * so they move to `{ table, reason }`.
 */
export function deprecationWarnings(
  config: Pick<ResolvedConfig, "blocks">,
): string[] {
  const exempt = config.blocks["audit"]?.options?.["exempt"];

  if (!Array.isArray(exempt)) {
    return [];
  }

  const bare = exempt.flatMap((entry: unknown) =>
    typeof entry === "string" ? [entry] : [],
  );

  return bare.length === 0
    ? []
    : [
        `blocks.audit.options.exempt has bare strings (${bare.join(", ")}). Write each as { table, reason }; a bare string becomes a doctor failure in the next minor.`,
      ];
}
