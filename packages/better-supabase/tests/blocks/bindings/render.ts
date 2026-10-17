/**
 * Renders the Vue, Svelte and Solid entries of every block with a controller
 * from one template, reading the factories in `src/blocks/<name>/client.ts`.
 * `pnpm --filter better-supabase gen:bindings` writes them; the drift test
 * fails when they are stale.
 */
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { format } from "oxfmt";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import oxfmt from "../../../../../oxfmt.config.ts";

const BLOCKS = fileURLToPath(new URL("../../../src/blocks/", import.meta.url));

export const FRAMEWORKS = ["vue", "svelte", "solid"] as const;
export type Framework = (typeof FRAMEWORKS)[number];

/** Hook names that don't follow `create<Name>Controller` to `use<Name>`. */
const HOOK_NAMES: Readonly<Record<string, string>> = {
  createUndoController: "useUndoStack",
};

const BUILTIN = new Set(["string", "number", "boolean", "unknown", "object"]);

export interface ControllerBinding {
  readonly factory: string;
  readonly hook: string;
  /** `<T>` or `<Id extends string, Scope extends ChecklistScope>`, or `""`. */
  readonly generics: string;
  readonly options: string;
  readonly snapshot: string;
  readonly actions: string;
  /** Whether the options take `auth` or `ports`, which the provider fills. */
  readonly env: boolean;
}

export interface BlockBindings {
  readonly block: string;
  readonly controllers: readonly ControllerBinding[];
  /** Type name to the module path it is imported from, relative to the binding. */
  readonly types: ReadonlyMap<string, string>;
}

const squash = (text: string): string =>
  text
    .replaceAll(/\s+/g, " ")
    .replace(/,\s*>$/, ">")
    .replace("< ", "<")
    .trim();

/** Splits `A<B, C>, D` at its top-level comma. */
function splitTop(text: string): [string, string] {
  let depth = 0;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (char === "<") depth += 1;
    else if (char === ">") depth -= 1;
    else if (char === "," && depth === 0) {
      return [text.slice(0, index).trim(), text.slice(index + 1).trim()];
    }
  }
  throw new Error(`expected two type arguments in ${text}`);
}

const paramNames = (generics: string): string[] =>
  generics === ""
    ? []
    : splitParams(generics.slice(1, -1)).map((param) => param.split(" ")[0]!);

function splitParams(text: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let start = 0;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (char === "<") depth += 1;
    else if (char === ">") depth -= 1;
    else if (char === "," && depth === 0) {
      parts.push(text.slice(start, index).trim());
      start = index + 1;
    }
  }
  parts.push(text.slice(start).trim());
  return parts.filter((part) => part !== "");
}

/** The type arguments that pass a declaration's parameters through: `<Id, Scope>`. */
export const typeArgs = (generics: string): string => {
  const names = paramNames(generics);
  return names.length === 0 ? "" : `<${names.join(", ")}>`;
};

function sourceOf(source: string, name: string): string {
  if (new RegExp(`^export (interface|type) ${name}\\b`, "m").test(source)) {
    return "../client.ts";
  }
  for (const match of source.matchAll(
    /^import type \{([^}]*)\} from "([^"]+)";/gm,
  )) {
    const names = match[1]!.split(",").map((part) => part.trim());
    if (names.includes(name)) {
      const from = match[2]!;
      return from.startsWith("./") ? `.${from}` : `../${from}`;
    }
  }
  throw new Error(`better-supabase: can't find where ${name} comes from`);
}

/** Whether the interface `name` (or one it extends in `source`) declares `auth` or `ports`. */
function usesEnv(source: string, name: string): boolean {
  const match = new RegExp(
    `^export interface ${name}(?:<[\\s\\S]*?>)?(?: extends ([\\s\\S]*?))? \\{([\\s\\S]*?)^\\}`,
    "m",
  ).exec(source);
  if (!match) return false;
  if (/^ {2}readonly (auth|ports)\b/m.test(match[2]!)) return true;
  const parents = (match[1] ?? "").match(/\b[A-Z]\w*/g) ?? [];
  return parents.some((parent) => usesEnv(source, parent));
}

/** Reads the controller factories of one block's `client.ts`. */
export function parseBlock(block: string, source: string): BlockBindings {
  const controllers: ControllerBinding[] = [];
  const types = new Map<string, string>();
  const factories = source.matchAll(
    /^export function (create\w+Controller)(<[\s\S]*?>)?\(\s*options: ([\s\S]*?),?\s*\): (\w+)(<[^>]*>)? \{/gm,
  );
  for (const [, factory, rawGenerics, options, alias] of factories) {
    const aliasMatch = new RegExp(
      `^export type ${alias}(?:<[^=]*>)? = Controller<([\\s\\S]*?)>;`,
      "m",
    ).exec(source);
    if (!aliasMatch) {
      throw new Error(`better-supabase: ${alias} is not a Controller alias`);
    }
    const [snapshot, actions] = splitTop(squash(aliasMatch[1]!));
    const generics = rawGenerics ? squash(rawGenerics) : "";
    const binding: ControllerBinding = {
      factory: factory!,
      hook:
        HOOK_NAMES[factory!] ??
        factory!.replace(/^create(\w+)Controller$/, "use$1"),
      generics,
      options: squash(options!),
      snapshot,
      actions,
      env: usesEnv(source, options!.trim().replace(/<[\s\S]*$/, "")),
    };
    controllers.push(binding);
    const own = new Set(paramNames(generics));
    const text = [generics, binding.options, snapshot, actions].join(" ");
    for (const [name] of text.matchAll(/\b[A-Z]\w*/g)) {
      if (own.has(name) || BUILTIN.has(name) || types.has(name)) continue;
      types.set(name, sourceOf(source, name));
    }
  }
  return { block, controllers, types };
}

/** Every block whose `client.ts` exports a controller factory. */
export async function readBlocks(): Promise<BlockBindings[]> {
  const blocks: BlockBindings[] = [];
  for (const entry of await readdir(BLOCKS, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const path = join(BLOCKS, entry.name, "client.ts");
    const source = await readFile(path, "utf-8").catch(() => undefined);
    if (source === undefined) continue;
    const parsed = parseBlock(entry.name, source);
    if (parsed.controllers.length > 0) blocks.push(parsed);
  }
  return blocks.toSorted((a, b) => a.block.localeCompare(b.block));
}

const BINDING_TYPE: Record<Framework, string> = {
  vue: "VueController",
  svelte: "SvelteController",
  solid: "SolidController",
};

const DOCS: Record<Framework, (factory: string) => string> = {
  vue: (factory) =>
    `\`${factory}\` as a Vue composable: \`state\` is a shallow ref of the snapshot. Call it in \`setup\` or an effect scope; the work starts on mount and the controller is disposed with the scope. \`auth\` and \`ports\` default to the client of \`app.use(betterSupabase(bs))\`.`,
  svelte: (factory) =>
    `\`${factory}\` as a Svelte readable store of the snapshot, with the actions on \`.actions\`. Call it in a component's script; the work starts on mount and the controller is disposed with the component. \`auth\` and \`ports\` default to the client of \`setBetterSupabase(bs)\`.`,
  solid: (factory) =>
    `\`${factory}\` as a Solid primitive: \`state()\` reads the snapshot. Call it in a component; the work starts on mount and the controller is disposed with the owner. \`auth\` and \`ports\` default to the client of \`<BetterSupabaseProvider client={bs}>\`.`,
};

/** Wraps `text` into comment lines of at most 77 columns. */
function wrap(text: string): string[] {
  const lines: string[] = [];
  let line = "";
  for (const word of text.split(" ")) {
    if (line !== "" && line.length + word.length + 1 > 77) {
      lines.push(line);
      line = word;
    } else line = line === "" ? word : `${line} ${word}`;
  }
  return [...lines, line];
}

function renderHook(framework: Framework, binding: ControllerBinding): string {
  const { factory, hook, generics, options, snapshot, actions, env } = binding;
  const docs = wrap(DOCS[framework](factory))
    .map((line) => ` * ${line}`)
    .join("\n");
  return `/**
${docs}
 */
export function ${hook}${generics}(
  options: BlockOptions<${options}>,
): ${BINDING_TYPE[framework]}<${snapshot}, ${actions}> {
  return useBlockController<${options}, ${snapshot}, ${actions}>(
    ${factory},
    options,${env ? "" : "\n    false,"}
  );
}
`;
}

/** The source of `src/blocks/<block>/<framework>/index.ts`. */
function renderBinding(framework: Framework, block: BlockBindings): string {
  const byModule = new Map<string, string[]>();
  for (const [name, from] of block.types) {
    byModule.set(from, [...(byModule.get(from) ?? []), name]);
  }
  const typeImports = [...byModule]
    .map(
      ([from, names]) =>
        `import type { ${names.toSorted().join(", ")} } from "${from}";`,
    )
    .join("\n");
  const typeExports = [...byModule]
    .map(
      ([from, names]) =>
        `export type { ${names.toSorted().join(", ")} } from "${from}";`,
    )
    .join("\n");
  const factories = block.controllers.map(({ factory }) => factory).toSorted();
  return `// Generated by \`pnpm --filter better-supabase gen:bindings\` from ../client.ts.
import type { BlockOptions } from "../../block-env.ts";
${typeImports}

import {
  type ${BINDING_TYPE[framework]},
  useBlockController,
} from "../../${framework}-controller.ts";
import { ${factories.join(", ")} } from "../client.ts";

export type { BlockOptions } from "../../block-env.ts";
export type { ${BINDING_TYPE[framework]} } from "../../${framework}-controller.ts";
${typeExports}

${block.controllers.map((binding) => renderHook(framework, binding)).join("\n")}`;
}

export interface RenderedFile {
  readonly path: string;
  readonly contents: string;
}

/** Every binding file, formatted as the repo formats it. */
export async function renderBindings(): Promise<RenderedFile[]> {
  const options = oxfmt;
  const files: RenderedFile[] = [];
  for (const block of await readBlocks()) {
    for (const framework of FRAMEWORKS) {
      const path = join(BLOCKS, block.block, framework, "index.ts");
      const { code, errors } = await format(
        path,
        renderBinding(framework, block),
        options,
      );
      if (errors.length > 0) {
        throw new Error(
          `oxfmt failed on ${path}: ${errors.map((error) => error.message).join("; ")}`,
        );
      }
      files.push({ path, contents: code });
    }
  }
  return files;
}
