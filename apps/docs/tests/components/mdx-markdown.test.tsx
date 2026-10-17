import { jsxComponents, renderToMarkdown } from "fumadocs-core/server";
import { describe, expect, it } from "vitest";

import {
  Callout,
  Card,
  Cards,
  markdownComponents,
  Step,
  Steps,
  Tab,
  Tabs,
  textOf,
  TypeTable,
} from "../../components/mdx-markdown";

describe("Markdown forms of MDX components", () => {
  it("writes a callout as a blockquote with its title", async () => {
    const out = await renderToMarkdown(
      <Callout title="Client bundles">{"First line.\n\nSecond line."}</Callout>,
    );

    expect(out).toBe(
      "> **Client bundles**\n>\n> First line.\n>\n> Second line.",
    );
  });

  it("labels an untitled callout by type", async () => {
    const out = await renderToMarkdown(<Callout type="warn">Careful.</Callout>);
    expect(out).toBe("> **Warning**\n>\n> Careful.");
  });

  it("numbers the heading of each step", async () => {
    const out = await renderToMarkdown(
      <Steps>
        <Step>{"### Install [#install]\n\nRun it."}</Step>
        <Step>{"### Configure [#configure]\n\nWrite it."}</Step>
        <Step>No heading.</Step>
      </Steps>,
    );

    expect(out).toBe(
      [
        "### 1. Install [#install]",
        "",
        "Run it.",
        "",
        "### 2. Configure [#configure]",
        "",
        "Write it.",
        "",
        "**Step 3.**",
        "",
        "No heading.",
      ].join("\n"),
    );
  });

  it("writes cards as a link list", async () => {
    const out = await renderToMarkdown(
      <Cards>
        <Card title="Quickstart" href="/docs/getting-started" />
        <Card title="Filtering" href="/docs/repository/filtering">
          Every operator.
        </Card>
      </Cards>,
    );

    expect(out).toBe(
      "- [Quickstart](/docs/getting-started)\n- [Filtering](/docs/repository/filtering): Every operator.",
    );
  });

  it("labels each tab from its value or the items list", async () => {
    const out = await renderToMarkdown(
      <Tabs items={["npm", "pnpm"]}>
        <Tab>npm i</Tab>
        <Tab value="pnpm">pnpm add</Tab>
      </Tabs>,
    );

    expect(out).toBe("**npm**\n\nnpm i\n\n**pnpm**\n\npnpm add");
  });

  it("writes a type table as a Markdown table", async () => {
    const out = await renderToMarkdown(
      <TypeTable
        type={{
          url: {
            type: (
              <span>
                <span>string</span>
              </span>
            ),
            required: true,
            description: <p>The API URL.</p>,
          },
          mode: {
            type: <span>{"'a' | 'b'"}</span>,
            default: <span>{"'a'"}</span>,
            deprecated: true,
          },
        }}
      />,
    );

    expect(out).toBe(
      [
        "| Name | Type | Default | Description |",
        "| --- | --- | --- | --- |",
        "| `url` | `string` |  | The API URL. |",
        `${String.raw`| ~~`}\`mode?\`${String.raw`~~ | `}\`'a' \\| 'b'\`` +
          ` | \`'a'\` |  |`,
      ].join("\n"),
    );
  });

  it("keeps components without a Markdown form as JSX", async () => {
    expect(Object.keys(markdownComponents)).not.toContain("Accordion");
    const Accordion = jsxComponents({})["Accordion"];

    if (Accordion === undefined) {
      throw new Error("expected a stub");
    }

    const out = await renderToMarkdown(
      <Accordion title="More">Body</Accordion>,
    );

    expect(out).toBe('<Accordion title="More">\nBody\n</Accordion>');
  });

  it("reads the text of a rendered node", () => {
    expect(
      textOf(
        <code>
          <span>Promise</span>
          {["<", "void", ">"]}
        </code>,
      ),
    ).toBe("Promise<void>");
  });
});
