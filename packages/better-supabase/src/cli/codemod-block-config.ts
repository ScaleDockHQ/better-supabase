import type { Codemod, ReviewLine } from "./codemod.ts";

const GENERATED_IMPORT =
  /import\s+(type\s+)?\{([^}]*)\}\s+from\s+(["'])([^"']*\/)blocks\.generated(\.ts)?\3;?/g;

const BLOCK_CONFIG = /^(?:type\s+)?blockConfig(?:\s+as\s+\w+)?$/;

/**
 * Moves `blockConfig` out of imports from `blocks.generated`. The data lives in
 * `blocks.config.ts`, so a client component that needs it no longer pulls in
 * every installed block client.
 */
function moveBlockConfigImport(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const rewritten = text.replaceAll(
    GENERATED_IMPORT,
    (
      whole: string,
      type: string | undefined,
      names: string,
      quote: string,
      directory: string,
      extension: string | undefined,
    ) => {
      const specifiers = names
        .split(",")
        .map((name) => name.trim())
        .filter(Boolean);

      const config = specifiers.filter((name) => BLOCK_CONFIG.test(name));

      if (config.length === 0) {
        return whole;
      }

      const rest = specifiers.filter((name) => !BLOCK_CONFIG.test(name));
      const ext = extension ?? "";
      const prefix = type ?? "";

      const lines = [
        `import ${prefix}{ ${config.join(", ")} } from ${quote}${directory}blocks.config${ext}${quote};`,
      ];

      if (rest.length > 0) {
        lines.push(
          `import ${prefix}{ ${rest.join(", ")} } from ${quote}${directory}blocks.generated${ext}${quote};`,
        );
      }

      return lines.join("\n");
    },
  );

  return { text: rewritten, review: [] };
}

export const CODEMOD_0_53: Codemod = {
  name: "0.53",
  description:
    "Import blockConfig from blocks.config.ts so client code stays small",
  source: moveBlockConfigImport,
};
