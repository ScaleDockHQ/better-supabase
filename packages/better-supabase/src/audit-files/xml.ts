import type { AuditFileSource, AuditParseLimits } from "./model.ts";

import { AuditFileError } from "./model.ts";

/** An element read into memory: its own text and its children. */
export interface XmlNode {
  /** The local name, without a namespace prefix. */
  readonly name: string;
  text: string;
  readonly children: XmlNode[];
}

type Token =
  | {
      readonly type: "open";
      readonly name: string;
      readonly selfClosed: boolean;
    }
  | { readonly type: "text"; readonly text: string }
  | { readonly type: "close"; readonly name: string };

const DEFAULT_DEPTH = 32;
const DEFAULT_TEXT = 1_048_576;
const DEFAULT_RECORD = 100_000;
const SLACK = 1024;

const NAMED: Readonly<Record<string, string>> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
};

const NAME_START = /[A-Za-z_:]/u;
const WHITESPACE = /\s/u;
const ENTITY = /&(#x[0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);/gu;
const TO_ESCAPE = /[&<>"]/gu;

function localName(name: string): string {
  const colon = name.indexOf(":");

  return colon === -1 ? name : name.slice(colon + 1);
}

function decodeEntities(raw: string): string {
  if (!raw.includes("&")) {
    return raw;
  }

  return raw.replaceAll(ENTITY, (_, body: string) => {
    if (body.startsWith("#")) {
      const code =
        body[1] === "x"
          ? Number.parseInt(body.slice(2), 16)
          : Math.trunc(Number(body.slice(1)));

      if (!Number.isInteger(code) || code < 0 || code > 0x10_ff_ff) {
        throw new AuditFileError(
          "AUDIT_XML_INVALID",
          `character reference &${body}; is not a character`,
        );
      }

      return String.fromCodePoint(code);
    }

    const named = NAMED[body];

    if (named === undefined) {
      // Entities from a DTD are refused: expanding them is how a small file
      // becomes a huge one.
      throw new AuditFileError(
        "AUDIT_XML_UNSUPPORTED",
        `entity &${body}; is not one of the five XML entities`,
      );
    }

    return named;
  });
}

async function* chunksOf(source: AuditFileSource): AsyncGenerator<string> {
  const decoder = new TextDecoder("utf-8", { fatal: true });

  if (typeof source === "string") {
    yield source;

    return;
  }

  if (source instanceof Uint8Array) {
    yield decoder.decode(source);

    return;
  }

  for await (const chunk of source) {
    yield typeof chunk === "string"
      ? chunk
      : decoder.decode(chunk, { stream: true });
  }

  const rest = decoder.decode();

  if (rest !== "") {
    yield rest;
  }
}

/**
 * A pull tokenizer over chunks. It keeps only the unread tail of the input, so
 * its memory is the largest token, bounded by `maxTextLength`.
 *
 * @yields {Token} The tokens of the document in order.
 */
async function* tokens(
  source: AuditFileSource,
  limits: AuditParseLimits,
): AsyncGenerator<Token> {
  const maxText = limits.maxTextLength ?? DEFAULT_TEXT;
  const chunks = chunksOf(source);
  let buffer = "";
  let done = false;
  const finished = (): boolean => done;
  let first = true;

  const fill = async (): Promise<boolean> => {
    if (done) {
      return false;
    }

    const next = await chunks.next();

    if (next.done === true) {
      done = true;

      return false;
    }

    buffer += next.value;

    if (first) {
      first = false;

      if (buffer.startsWith("\uFEFF")) {
        buffer = buffer.slice(1);
      }
    }

    return true;
  };

  const readTo = async (
    terminator: string,
    from: number,
    what: string,
  ): Promise<number> => {
    let start = from;

    for (;;) {
      const at = buffer.indexOf(terminator, start);

      if (at !== -1) {
        return at;
      }

      if (buffer.length > maxText + SLACK) {
        throw new AuditFileError(
          "AUDIT_XML_LIMIT",
          `${what} is longer than ${maxText} characters`,
        );
      }

      start = Math.max(0, buffer.length - terminator.length + 1);

      if (!(await fill())) {
        throw new AuditFileError("AUDIT_XML_INVALID", `${what} is not closed`);
      }
    }
  };

  const tagToken = async (): Promise<Token> => {
    let at = -1;
    let quote = "";
    let index = 1;

    for (;;) {
      while (index < buffer.length) {
        const character = buffer[index] ?? "";

        if (quote === "") {
          if (character === '"' || character === "'") {
            quote = character;
          } else if (character === ">") {
            at = index;
            break;
          }
        } else if (character === quote) {
          quote = "";
        }

        index += 1;
      }

      if (at !== -1) {
        break;
      }

      if (buffer.length > maxText + SLACK) {
        throw new AuditFileError("AUDIT_XML_LIMIT", "a tag is too long");
      }

      if (!(await fill())) {
        throw new AuditFileError("AUDIT_XML_INVALID", "a tag is not closed");
      }
    }

    const body = buffer.slice(1, at);

    buffer = buffer.slice(at + 1);

    if (body.startsWith("/")) {
      return { type: "close", name: localName(body.slice(1).trim()) };
    }

    const selfClosed = body.endsWith("/");
    const inner = selfClosed ? body.slice(0, -1) : body;
    let end = 0;

    while (end < inner.length && !WHITESPACE.test(inner[end] ?? "")) {
      end += 1;
    }

    const name = inner.slice(0, end);

    if (!NAME_START.test(name[0] ?? "")) {
      throw new AuditFileError(
        "AUDIT_XML_INVALID",
        `"<${name}" is not an element name`,
      );
    }

    // Attributes carry nothing in either format, so they are not read.
    return { type: "open", name: localName(name), selfClosed };
  };

  await fill();

  for (;;) {
    if (buffer === "" && !(await fill())) {
      return;
    }

    const lt = buffer.indexOf("<");

    if (lt !== 0) {
      if (lt === -1 && !finished()) {
        if (buffer.length > maxText) {
          throw new AuditFileError(
            "AUDIT_XML_LIMIT",
            `text is longer than ${maxText} characters`,
          );
        }

        if (await fill()) {
          continue;
        }
      }

      const end = lt === -1 ? buffer.length : lt;
      const text = buffer.slice(0, end);

      buffer = buffer.slice(end);

      if (text.trim() !== "") {
        yield { type: "text", text: decodeEntities(text) };
      }

      continue;
    }

    while (buffer.length < 9 && (await fill())) {
      // A tag start needs a few characters to tell what it is.
    }

    if (buffer.startsWith("<!--")) {
      const at = await readTo("-->", 4, "a comment");

      buffer = buffer.slice(at + 3);
    } else if (buffer.startsWith("<![CDATA[")) {
      const at = await readTo("]]>", 9, "a CDATA section");
      const text = buffer.slice(9, at);

      buffer = buffer.slice(at + 3);
      yield { type: "text", text };
    } else if (buffer.startsWith("<?")) {
      const at = await readTo("?>", 2, "a processing instruction");

      buffer = buffer.slice(at + 2);
    } else if (buffer.startsWith("<!")) {
      const at = await readTo(">", 2, "a declaration");

      if (buffer.slice(0, at).includes("[")) {
        throw new AuditFileError(
          "AUDIT_XML_UNSUPPORTED",
          "a DOCTYPE with an internal subset is not supported",
        );
      }

      buffer = buffer.slice(at + 1);
    } else {
      yield await tagToken();
    }
  }
}

/** What a walk over a file yields. */
export type WalkEvent =
  | { readonly type: "open"; readonly path: string }
  | { readonly type: "close"; readonly path: string }
  | { readonly type: "leaf"; readonly path: string; readonly text: string }
  | { readonly type: "node"; readonly path: string; readonly node: XmlNode }
  | { readonly type: "unmapped"; readonly path: string };

/** Which paths a format maps, as `A/B/C` strings from the root element. */
export interface WalkSpec {
  /**
   * Elements whose whole subtree is read into a node, each with the relative
   * paths inside it that the adapter reads.
   */
  readonly records: ReadonlyMap<string, ReadonlySet<string>>;
  /** Elements the walk enters; their children are mapped or reported. */
  readonly containers: ReadonlySet<string>;
  /** Elements with text only that the adapter reads. */
  readonly leaves: ReadonlySet<string>;
}

function collectUnknown(
  node: XmlNode,
  known: ReadonlySet<string>,
  prefix: string,
  found: Set<string>,
): void {
  for (const child of node.children) {
    const path = prefix === "" ? child.name : `${prefix}/${child.name}`;

    if (known.has(path)) {
      collectUnknown(child, known, path, found);
    } else {
      found.add(path);
    }
  }
}

interface Open {
  readonly path: string;
  readonly root: XmlNode;
}

/**
 * Walks a file and sorts every element into a record, a container, a leaf or
 * unmapped. An unmapped element is reported once and its subtree skipped, so
 * nothing is dropped without a trace.
 *
 * @yields {WalkEvent} Record, container, leaf and unmapped events in document
 *   order.
 */
export async function* walk(
  source: AuditFileSource,
  spec: WalkSpec,
  limits: AuditParseLimits = {},
): AsyncGenerator<WalkEvent> {
  const maxDepth = limits.maxDepth ?? DEFAULT_DEPTH;
  const maxRecord = limits.maxRecordElements ?? DEFAULT_RECORD;
  const stack: string[] = [];
  let skipping = 0;
  let record: Open | undefined;
  let recordStack: XmlNode[] = [];
  let recordSize = 0;
  let leafText: string | undefined;
  let rootSeen = false;

  const close = function* close(name: string): Generator<WalkEvent> {
    if (stack.at(-1) !== name) {
      throw new AuditFileError(
        "AUDIT_XML_INVALID",
        `</${name}> closes <${stack.at(-1) ?? ""}>`,
      );
    }

    const path = stack.join("/");

    stack.pop();

    if (skipping > 0) {
      skipping -= 1;

      return;
    }

    if (record !== undefined) {
      recordStack.pop();

      if (recordStack.length === 0) {
        const finished: Open = record;
        const known = spec.records.get(finished.path) ?? new Set<string>();
        const unknown = new Set<string>();

        collectUnknown(finished.root, known, "", unknown);
        record = undefined;

        for (const inner of unknown) {
          yield { type: "unmapped", path: `${finished.path}/${inner}` };
        }

        yield { type: "node", path, node: finished.root };
      }

      return;
    }

    if (leafText !== undefined) {
      const text = leafText.trim();

      leafText = undefined;

      yield { type: "leaf", path, text };

      return;
    }

    yield { type: "close", path };
  };

  for await (const token of tokens(source, limits)) {
    if (token.type === "text") {
      if (skipping === 0) {
        const target = recordStack.at(-1);

        if (record !== undefined && target !== undefined) {
          target.text += token.text;
        } else if (leafText !== undefined) {
          leafText += token.text;
        }
      }

      continue;
    }

    if (token.type === "close") {
      yield* close(token.name);

      continue;
    }

    if (stack.length === 0) {
      if (rootSeen) {
        throw new AuditFileError(
          "AUDIT_XML_INVALID",
          "the file has more than one root element",
        );
      }

      rootSeen = true;
    }

    if (stack.length >= maxDepth) {
      throw new AuditFileError(
        "AUDIT_XML_LIMIT",
        `elements nest deeper than ${maxDepth} levels`,
      );
    }

    stack.push(token.name);

    if (skipping > 0) {
      skipping += 1;
    } else if (record === undefined) {
      const path = stack.join("/");

      if (spec.records.has(path)) {
        const root: XmlNode = { name: token.name, text: "", children: [] };

        record = { path, root };
        recordStack = [root];
        recordSize = 1;
      } else if (spec.leaves.has(path)) {
        leafText = "";
      } else if (spec.containers.has(path) && leafText === undefined) {
        yield { type: "open", path };
      } else {
        yield { type: "unmapped", path };
        skipping = 1;
      }
    } else {
      recordSize += 1;

      if (recordSize > maxRecord) {
        throw new AuditFileError(
          "AUDIT_XML_LIMIT",
          `a record has more than ${maxRecord} elements`,
        );
      }

      const node: XmlNode = { name: token.name, text: "", children: [] };

      recordStack.at(-1)?.children.push(node);
      recordStack.push(node);
    }

    if (token.selfClosed) {
      yield* close(token.name);
    }
  }

  if (stack.length > 0) {
    throw new AuditFileError(
      "AUDIT_XML_INVALID",
      `element <${stack.at(-1) ?? ""}> is not closed`,
    );
  }

  if (!rootSeen) {
    throw new AuditFileError("AUDIT_XML_INVALID", "the file has no elements");
  }
}

/** The text of the first child called `name`, trimmed; `undefined` if none. */
export function childText(node: XmlNode, name: string): string | undefined {
  const text = node.children.find((child) => child.name === name)?.text.trim();

  return text === undefined || text === "" ? undefined : text;
}

export function childrenOf(node: XmlNode, name: string): readonly XmlNode[] {
  return node.children.filter((child) => child.name === name);
}

export function childNode(node: XmlNode, name: string): XmlNode | undefined {
  return node.children.find((child) => child.name === name);
}

const ESCAPES: Readonly<Record<string, string>> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
};

/** Escapes text; characters XML 1.0 forbids are dropped. */
function escapeText(value: string): string {
  let kept = "";

  for (const character of value) {
    const code = character.codePointAt(0) ?? 0;

    if (code >= 0x20 || code === 0x09 || code === 0x0a || code === 0x0d) {
      kept += character;
    }
  }

  return kept.replaceAll(
    TO_ESCAPE,
    (character) => ESCAPES[character] ?? character,
  );
}

/** An element with text, or nothing when the value is `undefined`. */
export function tag(name: string, value: string | undefined): string {
  return value === undefined ? "" : `<${name}>${escapeText(value)}</${name}>`;
}

/** An element around already rendered children; nothing when empty. */
export function wrap(name: string, children: readonly string[]): string {
  const body = children.join("");

  return body === "" ? "" : `<${name}>${body}</${name}>`;
}
