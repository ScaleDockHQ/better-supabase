/**
 * Source rewrites for `better-supabase codemod`. A small scanner masks
 * strings, template literals and comments, so renames only touch code; there
 * is no parser dependency, so each transform is a narrow, mechanical rename.
 */

export interface Codemod {
  readonly name: string;
  readonly description: string;
  /** Exported names, renamed in imports from `better-supabase` and where the import is used. */
  readonly imports?: Readonly<Record<string, string>>;
  /** Member names, renamed after a `.` anywhere in code. */
  readonly members?: readonly MemberRename[];
  /** JSX props on one component. */
  readonly props?: readonly PropRename[];
  /** Keys of the options object a named call takes, at its top level. */
  readonly options?: readonly OptionRename[];
  /** Changes too ambiguous to rewrite; matching lines are listed for review. */
  readonly review?: readonly ReviewHint[];
}

export interface MemberRename {
  readonly from: string;
  readonly to: string;
  /** Skip a member followed by `(`, when the old name is still a method. */
  readonly notCalled?: boolean;
}

export interface PropRename {
  readonly component: string;
  readonly from: string;
  readonly to: string;
}

export interface OptionRename {
  readonly call: string;
  readonly from: string;
  readonly to: string;
}

export interface ReviewHint {
  readonly pattern: RegExp;
  readonly message: string;
}

export const CODEMODS: Readonly<Record<string, Codemod>> = {
  "0.4": {
    name: "0.4",
    description: "Renames from 0.3 to 0.4 (the naming page lists them)",
    imports: {
      createBrowser: "createClient",
      BetterBrowser: "BetterClient",
      BrowserOptions: "ClientOptions",
      BrowserAuth: "ClientAuth",
      BetterEnv: "HonoEnv",
      HandlerOptions: "MiddlewareOptions",
      Queries: "BetterQueries",
      CreateQueriesOptions: "QueriesOptions",
      Postgres: "BetterPostgres",
      DefineSupabaseOptions: "SupabaseOptions",
    },
    members: [
      { from: "serverFor", to: "contextForSession" },
      { from: "toORPCError", to: "toOrpcError" },
      { from: "$table", to: "$tableName", notCalled: true },
    ],
    props: [
      { component: "BetterSupabaseProvider", from: "browser", to: "client" },
    ],
    review: [
      {
        pattern: /\.server\(\)/,
        message:
          "`next.server()` is `bs.context()` on the createNext() instance",
      },
      {
        pattern: /\.handle\(\)/,
        message: "Hono's `bs.handle()` is `bs.handler()`",
      },
      {
        pattern: /\bmcp\.handler\b/,
        message: "`mcp.handler` is `bs.endpoint`",
      },
      { pattern: /\.sb\b/, message: "`client.sb` is `client.betterSupabase`" },
      {
        pattern: /\btestExecutor\(\s*\{[^}]*\bsb\b/,
        message: "`{ sb }` in testExecutor is `{ betterSupabase }`",
      },
    ],
  },
  "0.5": {
    name: "0.5",
    description:
      "Renames from 0.4 to 0.5: createMcp's scopes is advertisedScopes",
    options: [{ call: "createMcp", from: "scopes", to: "advertisedScopes" }],
  },
  "0.6": {
    name: "0.6",
    description:
      "Changes from 0.5 to 0.6: kits become blocks and modules, org becomes organization, $rpc returns table rows and records in the configured casing, and bucket publicUrl() and path() return a Result",
    imports: {
      KitEvent: "BlockEvent",
      KitEventMap: "BlockEventMap",
      KitEventType: "BlockEventType",
      KitEventMeta: "BlockEventMeta",
      KitEventPattern: "BlockEventPattern",
      KitEventsMatching: "BlockEventsMatching",
      onKitEvent: "onBlockEvent",
      forwardKitEvents: "forwardBlockEvents",
      ForwardKitOptions: "ForwardBlockOptions",
      KIT_ATTRIBUTES: "BLOCK_ATTRIBUTES",
      kitCloudEvent: "blockCloudEvent",
      kitEventAttributes: "blockEventAttributes",
      traceKitEvents: "traceBlockEvents",
      KitTransport: "BlockTransport",
      OrgEventData: "OrganizationEventData",
      createOrgs: "createOrganizations",
      Orgs: "Organizations",
      OrgsOptions: "OrganizationsOptions",
      CreateOrgOptions: "CreateOrganizationOptions",
      OrgAttributes: "OrganizationAttributes",
      orgLogoBucket: "organizationLogoBucket",
      OrgLogoBucketOptions: "OrganizationLogoBucketOptions",
      KitsConfig: "ModulesConfig",
      KitModuleConfig: "ModuleConfig",
      KitMode: "ModuleMode",
      AccessKitConfig: "AccessModuleConfig",
      renderKit: "renderModules",
      kitLayout: "moduleLayout",
      kitPermissionKeys: "modulePermissionKeys",
      kitDeprecations: "moduleDeprecations",
      kitFilePaths: "moduleFilePaths",
      kitFileVersion: "moduleFileVersion",
      sameKitFile: "sameModuleFile",
      kitIdType: "moduleIdType",
      isKitIdType: "isModuleIdType",
      KIT_ID_TYPES: "MODULE_ID_TYPES",
      KitIdType: "ModuleIdType",
      KitContext: "ModuleContext",
      KitLayout: "ModuleLayout",
      KitFile: "ModuleFile",
      KitNames: "ModuleNames",
      KitTableSpec: "ModuleTableSpec",
      KitContractFunction: "ModuleContractFunction",
      KitDeprecation: "ModuleDeprecation",
      KitPermissionKey: "ModulePermissionKey",
      KitUpgrade: "ModuleUpgrade",
      KitUpgradePlan: "ModuleUpgradePlan",
      InstalledKitModule: "InstalledModule",
    },
    options: [
      { call: "defineSupabase", from: "maxUrlLength", to: "urlLengthLimit" },
    ],
    review: [
      {
        pattern:
          /from\s*["']better-supabase\/(orgs|jobs|notifications|webhooks)["']/,
        message:
          "This subpath moved under `better-supabase/blocks/` (`orgs` is `blocks/organizations`; the outbox, entitlements and audit retention left `jobs` for their own blocks); the 0.5 to 0.6 guide maps each export",
      },
      {
        pattern:
          /\bcreateInbox\b[^\n]*from\s*["']better-supabase\/(blocks\/)?jobs["']/,
        message:
          "The webhook inbox is `createWebhookInbox` from `better-supabase/blocks/jobs`; `createInbox` is now the conversation inbox in `blocks/inbox`",
      },
      {
        pattern: /\$rpc\s*(<|\()/,
        message:
          "`$rpc` now returns table rows and `returns table (...)` records in the configured casing, with codecs applied: drop a snake-to-camel mapping of the result, or pass `{ raw: true }` to keep database names. Scalar results and `returns table` columns are now `| null` unless `functions.<name>.notNull` says otherwise",
      },
      {
        pattern: /\.publicUrl\s*\(/,
        message:
          "A connected bucket's `publicUrl()` returns a `Result` instead of throwing: read `.data` (`null` on an error) or check `.ok`",
      },
      {
        pattern: /\.path\s*\(\s*\{/,
        message:
          "A bucket definition's `path(values)` returns a `Result` instead of throwing, like the connected client's `path()`: read `.data` (`null` on an error) or check `.ok`",
      },
    ],
  },
};

/** `[start, end)` ranges of code, outside strings, template literals and comments. */
export function codeRanges(text: string): [number, number][] {
  const ranges: [number, number][] = [];
  let start = 0;
  let index = 0;
  const skip = (end: number): void => {
    if (index > start) ranges.push([start, index]);
    index = end;
    start = end;
  };
  while (index < text.length) {
    const char = text[index]!;
    const next = text[index + 1];
    if (char === "/" && next === "/") {
      const end = text.indexOf("\n", index);
      skip(end === -1 ? text.length : end);
    } else if (char === "/" && next === "*") {
      const end = text.indexOf("*/", index + 2);
      skip(end === -1 ? text.length : end + 2);
    } else if (char === '"' || char === "'" || char === "`") {
      let end = index + 1;
      while (end < text.length && text[end] !== char) {
        if (text[end] === "\\") end += 1;
        if (char !== "`" && text[end] === "\n") break;
        end += 1;
      }
      skip(text[end] === char ? end + 1 : Math.min(end, text.length));
    } else {
      index += 1;
    }
  }
  if (index > start) ranges.push([start, index]);
  return ranges;
}

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

function applyEdits(text: string, edits: readonly Edit[]): string {
  let out = "";
  let cursor = 0;
  for (const edit of [...edits].sort((a, b) => a.start - b.start)) {
    if (edit.start < cursor) continue;
    out += text.slice(cursor, edit.start) + edit.text;
    cursor = edit.end;
  }
  return out + text.slice(cursor);
}

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

function inCode(ranges: readonly [number, number][], index: number): boolean {
  let low = 0;
  let high = ranges.length - 1;
  while (low <= high) {
    const middle = (low + high) >> 1;
    const [start, end] = ranges[middle]!;
    if (index < start) high = middle - 1;
    else if (index >= end) low = middle + 1;
    else return true;
  }
  return false;
}

const OPENING = "({[";
const CLOSING = ")}]";

/** Matches of `pattern` that start in code. */
function codeMatches(
  text: string,
  pattern: RegExp,
  ranges: readonly [number, number][],
): RegExpExecArray[] {
  return [...text.matchAll(pattern)].filter((match) =>
    inCode(ranges, match.index),
  );
}

const IMPORT =
  /\b(import|export)\s+(type\s+)?\{([^}]*)\}\s*from\s*(["'])better-supabase(?:\/[\w./-]*)?\4/g;

function renameImports(
  text: string,
  renames: Readonly<Record<string, string>>,
): { text: string; locals: Set<string> } {
  const ranges = codeRanges(text);
  const locals = new Set<string>();
  const edits: Edit[] = [];
  for (const match of codeMatches(text, IMPORT, ranges)) {
    const list = match[3]!;
    const listStart = match.index + match[0].indexOf("{") + 1;
    const renamed = list.replaceAll(
      /(\btype\s+)?([\w$]+)(\s+as\s+[\w$]+)?/g,
      (spec, type: string | undefined, name: string, alias?: string) => {
        const to = renames[name];
        if (to === undefined) return spec;
        if (alias === undefined && match[1] === "import") locals.add(name);
        return `${type ?? ""}${to}${alias ?? ""}`;
      },
    );
    if (renamed !== list) {
      edits.push({
        start: listStart,
        end: listStart + list.length,
        text: renamed,
      });
    }
  }
  return { text: applyEdits(text, edits), locals };
}

function renameIdentifiers(
  text: string,
  renames: ReadonlyMap<string, string>,
): string {
  if (renames.size === 0) return text;
  const ranges = codeRanges(text);
  const names = [...renames.keys()].map(escapeRegExp).join("|");
  const pattern = new RegExp(`(?<![\\w$.])(?:${names})(?![\\w$])`, "g");
  return applyEdits(
    text,
    codeMatches(text, pattern, ranges).map((match) => ({
      start: match.index,
      end: match.index + match[0].length,
      text: renames.get(match[0])!,
    })),
  );
}

function renameMembers(text: string, members: readonly MemberRename[]): string {
  const ranges = codeRanges(text);
  const edits = members.flatMap((member) =>
    codeMatches(
      text,
      new RegExp(
        `\\.${escapeRegExp(member.from)}(?![\\w$])${member.notCalled === true ? "(?!\\s*\\()" : ""}`,
        "g",
      ),
      ranges,
    ).map((match) => ({
      start: match.index,
      end: match.index + match[0].length,
      text: `.${member.to}`,
    })),
  );
  return applyEdits(text, edits);
}

function renameProps(text: string, props: readonly PropRename[]): string {
  const ranges = codeRanges(text);
  const edits: Edit[] = [];
  for (const prop of props) {
    const tag = new RegExp(`<${escapeRegExp(prop.component)}(?![\\w$.])`, "g");
    for (const match of codeMatches(text, tag, ranges)) {
      let depth = 0;
      for (
        let index = match.index + match[0].length;
        index < text.length;
        index += 1
      ) {
        if (!inCode(ranges, index)) continue;
        const char = text[index]!;
        if (char === "{") depth += 1;
        else if (char === "}") depth -= 1;
        else if (char === ">" && depth === 0) break;
        if (
          depth === 0 &&
          /\s/.test(text[index - 1] ?? "") &&
          text.startsWith(`${prop.from}=`, index)
        ) {
          edits.push({
            start: index,
            end: index + prop.from.length,
            text: prop.to,
          });
        }
      }
    }
  }
  return applyEdits(text, edits);
}

/** The index after the bracket that closes the one at `open`, in code only. */
function closing(
  text: string,
  open: number,
  ranges: readonly [number, number][],
): number {
  let depth = 0;
  for (let index = open; index < text.length; index += 1) {
    if (!inCode(ranges, index)) continue;
    const char = text[index]!;
    if (OPENING.includes(char)) depth += 1;
    else if (CLOSING.includes(char)) {
      depth -= 1;
      if (depth === 0) return index + 1;
    }
  }
  return text.length;
}

/** Calls `visit(index, depth)` for each code character from `open` to its closing bracket. */
function walkBrackets(
  text: string,
  open: number,
  ranges: readonly [number, number][],
  visit: (index: number, depth: number, char: string) => void,
): void {
  const end = closing(text, open, ranges);
  let depth = 0;
  for (let index = open; index < end; index += 1) {
    if (!inCode(ranges, index)) continue;
    const char = text[index]!;
    if (OPENING.includes(char)) depth += 1;
    else if (CLOSING.includes(char)) depth -= 1;
    visit(index, depth, char);
  }
}

/** Where `key` is a top-level key of the object literal at `open`. */
function topLevelKeys(
  text: string,
  open: number,
  key: string,
  ranges: readonly [number, number][],
): { readonly index: number; readonly shorthand: boolean }[] {
  const keys: { index: number; shorthand: boolean }[] = [];
  let previous = "";
  walkBrackets(text, open, ranges, (index, depth, char) => {
    if (
      depth === 1 &&
      (previous === "{" || previous === ",") &&
      text.startsWith(key, index) &&
      !/[\w$]/.test(text[index + key.length] ?? "")
    ) {
      const after = /^\s*(\S)/.exec(text.slice(index + key.length))?.[1];
      if (after === ":") keys.push({ index, shorthand: false });
      else if (after === "," || after === "}") {
        keys.push({ index, shorthand: true });
      }
    }
    if (depth === 1 && !/\s/.test(char)) previous = char;
  });
  return keys;
}

function renameOptions(text: string, options: readonly OptionRename[]): string {
  const ranges = codeRanges(text);
  const edits: Edit[] = [];
  for (const option of options) {
    const call = new RegExp(
      `(?<![\\w$.])${escapeRegExp(option.call)}\\s*(?:<[^>]*>)?\\s*\\(`,
      "g",
    );
    for (const match of codeMatches(text, call, ranges)) {
      const objects: number[] = [];
      walkBrackets(
        text,
        match.index + match[0].length - 1,
        ranges,
        (index, depth, char) => {
          if (depth === 2 && char === "{") objects.push(index);
        },
      );
      for (const object of objects) {
        for (const { index, shorthand } of topLevelKeys(
          text,
          object,
          option.from,
          ranges,
        )) {
          edits.push({
            start: index,
            end: index + option.from.length,
            text: shorthand ? `${option.to}: ${option.from}` : option.to,
          });
        }
      }
    }
  }
  return applyEdits(text, edits);
}

export interface CodemodResult {
  readonly text: string;
  /** 1-based lines that need a manual change, with the reason. */
  readonly review: readonly {
    readonly line: number;
    readonly message: string;
  }[];
}

/** Applies one codemod to a source file. */
export function applyCodemod(codemod: Codemod, source: string): CodemodResult {
  let text = source;
  if (codemod.imports) {
    const imported = renameImports(text, codemod.imports);
    text = renameIdentifiers(
      imported.text,
      new Map(
        [...imported.locals].map((name) => [name, codemod.imports![name]!]),
      ),
    );
  }
  if (codemod.members) text = renameMembers(text, codemod.members);
  if (codemod.props) text = renameProps(text, codemod.props);
  if (codemod.options) text = renameOptions(text, codemod.options);
  const review = (codemod.review ?? []).flatMap((hint) =>
    text
      .split("\n")
      .flatMap((line, index) =>
        hint.pattern.test(line)
          ? [{ line: index + 1, message: hint.message }]
          : [],
      ),
  );
  return { text, review };
}
