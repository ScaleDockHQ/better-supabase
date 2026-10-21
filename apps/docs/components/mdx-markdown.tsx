import type { MDXComponents } from "mdx/types";
import type { ReactNode } from "react";

import { asMarkdown, md } from "fumadocs-core/server";
import { Children, isValidElement } from "react";

/**
 * The Markdown forms of the MDX components the docs use, for `llms-full.txt`,
 * the `.md` routes, Ask AI and the docs MCP server. Only components listed here
 * are rendered; any other JSX element is written out as JSX.
 */

const CALLOUT_LABELS = new Map([
  ["info", "Note"],
  ["warn", "Warning"],
  ["warning", "Warning"],
  ["error", "Important"],
  ["success", "Tip"],
  ["idea", "Tip"],
]);

type CalloutProps = { title?: ReactNode; type?: string; children?: ReactNode };

export async function Callout({
  title,
  type,
  children,
}: CalloutProps): Promise<string> {
  if (!asMarkdown()) {
    return "";
  }

  const label = title ?? CALLOUT_LABELS.get(type ?? "info") ?? "Note";

  return md.linePrefix("> ")`**${label}**\n\n${children}`;
}

type StepProps = { index?: number; children?: ReactNode };

const HEADING = /^(#{1,6}) /u;

export async function Step({ index, children }: StepProps): Promise<string> {
  if (!asMarkdown()) {
    return "";
  }

  const body = (await md`${children}`).trim();

  if (index === undefined) {
    return `\n${body}\n\n`;
  }

  if (HEADING.test(body)) {
    return `\n${body.replace(HEADING, `$1 ${index}. `)}\n\n`;
  }

  return `\n**Step ${index}.**\n\n${body}\n\n`;
}

export async function Steps({
  children,
}: {
  children?: ReactNode;
}): Promise<string> {
  if (!asMarkdown()) {
    return "";
  }

  let index = 0;

  const numbered = Children.map(children, (child) =>
    isValidElement<StepProps>(child) && child.type === Step ? (
      <Step index={(index += 1)}>{child.props.children}</Step>
    ) : (
      child
    ),
  );

  return md`${numbered}`;
}

type CardProps = {
  title?: ReactNode;
  href?: string;
  description?: ReactNode;
  children?: ReactNode;
};

function inline(text: string): string {
  return text.trim().replaceAll(/\s*\n\s*/gu, " ");
}

export async function Card({
  title,
  href,
  description,
  children,
}: CardProps): Promise<string> {
  if (!asMarkdown()) {
    return "";
  }

  const label = inline(await md`${title}`);
  const detail = inline(await md`${description ?? children}`);
  const link = href === undefined ? label : `[${label}](${href})`;

  return `- ${link}${detail === "" ? "" : `: ${detail}`}\n`;
}

export async function Cards({
  children,
}: {
  children?: ReactNode;
}): Promise<string> {
  if (!asMarkdown()) {
    return "";
  }

  const items = (await md`${children}`).replaceAll(/\n{2,}/gu, "\n").trim();

  return items === "" ? "" : `\n${items}\n\n`;
}

type TabProps = {
  value?: string | undefined;
  title?: ReactNode;
  children?: ReactNode;
};

export async function Tab({
  value,
  title,
  children,
}: TabProps): Promise<string> {
  if (!asMarkdown()) {
    return "";
  }

  const label = inline(await md`${title ?? value ?? ""}`);
  const body = (await md`${children}`).trim();

  return label === "" ? `\n${body}\n\n` : `\n**${label}**\n\n${body}\n\n`;
}

export async function Tabs({
  items,
  children,
}: {
  items?: readonly string[];
  children?: ReactNode;
}): Promise<string> {
  if (!asMarkdown()) {
    return "";
  }

  let index = 0;

  const labelled = Children.map(children, (child) => {
    if (!isValidElement<TabProps>(child) || child.type !== Tab) {
      return child;
    }

    const value = child.props.value ?? items?.[index];
    index += 1;

    return <Tab {...child.props} value={value} />;
  });

  return md`${labelled}`;
}

/** Plain text of a rendered node, such as a syntax-highlighted type. */
export function textOf(node: ReactNode): string {
  return Children.toArray(node)
    .map((child) =>
      isValidElement<{ children?: ReactNode }>(child)
        ? textOf(child.props.children)
        : String(child),
    )
    .join("");
}

type TypeEntry = {
  type: ReactNode;
  typeDescription?: ReactNode;
  description?: ReactNode;
  default?: ReactNode;
  required?: boolean;
  deprecated?: boolean;
};

function cell(text: string): string {
  return inline(text).replaceAll("|", String.raw`\|`);
}

function code(text: string): string {
  const value = inline(text);

  if (value === "") {
    return "";
  }

  const fence = value.includes("`") ? "``" : "`";

  return cell(`${fence}${value}${fence}`);
}

export async function TypeTable({
  type,
}: {
  type: Record<string, TypeEntry>;
}): Promise<string> {
  if (!asMarkdown()) {
    return "";
  }

  const rows = await Promise.all(
    Object.entries(type).map(async ([name, entry]) => {
      const prop = `${name}${entry.required === true ? "" : "?"}`;
      const description = cell(await md`${entry.description}`);

      return `| ${entry.deprecated === true ? `~~${code(prop)}~~` : code(prop)} | ${code(
        textOf(entry.typeDescription ?? entry.type),
      )} | ${code(textOf(entry.default))} | ${description} |`;
    }),
  );

  return [
    "",
    "| Name | Type | Default | Description |",
    "| --- | --- | --- | --- |",
    ...rows,
    "",
    "",
  ].join("\n");
}

/** The components `getText("processed")` renders; everything else stays JSX. */
export const markdownComponents: MDXComponents = {
  Callout,
  Card,
  Cards,
  Step,
  Steps,
  Tab,
  Tabs,
  TypeTable,
};
