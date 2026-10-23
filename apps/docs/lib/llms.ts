import type { Folder, Item, Node, Root } from "fumadocs-core/page-tree";
import type { ReactNode } from "react";

import * as v from "valibot";

import { markdownUrl } from "./shared";

export interface LLMIndexOptions {
  readonly title: string;
  /** The `> summary` line under the title. */
  readonly summary: string;
  /** Prose between the summary and the first section. */
  readonly details: string;
  /** The description of a page item, from its frontmatter. */
  readonly describe: (item: Item) => string | undefined;
  /** An absolute URL on the public site for a path such as `/docs/cli.md`. */
  readonly absolute: (path: string) => string;
  /** Links listed under `## Optional`, which agents may skip. */
  readonly optional: readonly {
    title: string;
    url: string;
    description: string;
  }[];
}

/**
 * Sidebar names come from frontmatter titles and `meta.json`, so they are
 * strings.
 */
function text(name: ReactNode): string {
  return v.is(v.string(), name) ? name : "";
}

function link(
  title: string,
  url: string,
  description: string | undefined,
): string {
  const escaped = title.replaceAll(/([[\]])/gu, "\\$1");
  const target = url.replaceAll(/([()])/gu, "\\$1");
  const detail = description?.trim();

  return detail === undefined || detail === ""
    ? `[${escaped}](${target})`
    : `[${escaped}](${target}): ${detail}`;
}

function formatItem(
  item: Item,
  options: LLMIndexOptions,
  depth: number,
): string {
  const url =
    item.external === true ? item.url : options.absolute(markdownUrl(item.url));

  return `${"  ".repeat(depth)}- ${link(text(item.name), url, options.describe(item))}`;
}

function folderChildren(folder: Folder): Node[] {
  return folder.index === undefined
    ? folder.children
    : [folder.index, ...folder.children];
}

function formatNodes(
  nodes: readonly Node[],
  options: LLMIndexOptions,
  depth: number,
  section: string,
): string[] {
  const lines: string[] = [];

  for (const node of nodes) {
    switch (node.type) {
      case "page": {
        lines.push(formatItem(node, options, depth));
        break;
      }

      case "folder": {
        const name = text(node.name);

        // A folder named like its section adds a level that says nothing new.
        if (depth === 0 && name === section) {
          lines.push(
            ...formatNodes(folderChildren(node), options, depth, section),
          );
          break;
        }

        lines.push(
          `${"  ".repeat(depth)}- ${name}`,
          ...formatNodes(folderChildren(node), options, depth + 1, section),
        );
        break;
      }

      case "separator": {
        break;
      }

      default: {
        const exhaustive: never = node;
        throw new Error(`Unknown page tree node ${String(exhaustive)}`);
      }
    }
  }

  return lines;
}

/** A sidebar tab: a root folder, rendered as its own `##` section. */
function isRootFolder(node: Node): node is Folder {
  return (
    node.type === "folder" && node.root !== undefined && node.root !== false
  );
}

/**
 * `llms.txt` in the shape llmstxt.org describes: a title, a summary, prose,
 * then one `##` section per sidebar tab or separator, with absolute Markdown
 * links.
 */
export function formatLLMIndex(tree: Root, options: LLMIndexOptions): string {
  const sections: { title: string; nodes: Node[] }[] = [
    { title: "", nodes: [] },
  ];

  for (const node of tree.children) {
    if (node.type === "separator") {
      sections.push({ title: text(node.name), nodes: [] });
    } else if (isRootFolder(node)) {
      sections.push({ title: text(node.name), nodes: folderChildren(node) });
    } else {
      sections.at(-1)?.nodes.push(node);
    }
  }

  const out = [
    `# ${options.title}`,
    "",
    `> ${options.summary}`,
    "",
    options.details,
  ];

  for (const section of sections) {
    if (section.nodes.length === 0) {
      continue;
    }

    out.push("");

    if (section.title !== "") {
      out.push(`## ${section.title}`, "");
    }

    out.push(...formatNodes(section.nodes, options, 0, section.title));
  }

  if (options.optional.length > 0) {
    out.push("", "## Optional", "");

    for (const entry of options.optional) {
      out.push(`- ${link(entry.title, entry.url, entry.description)}`);
    }
  }

  return `${out.join("\n")}\n`;
}
