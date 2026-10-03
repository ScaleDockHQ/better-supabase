import type { MDXComponents } from "mdx/types";
import type { ComponentProps } from "react";

import { Step, Steps } from "fumadocs-ui/components/steps";
import { Tab, Tabs } from "fumadocs-ui/components/tabs";
import { TypeTable } from "fumadocs-ui/components/type-table";
import defaultMdxComponents from "fumadocs-ui/mdx";

/** A wide table scrolls, so its wrapper takes keyboard focus to scroll it. */
function Table(props: ComponentProps<"table">) {
  return (
    <section
      className="prose-no-margin relative my-6 overflow-auto"
      // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- a scrolling region needs keyboard focus (axe scrollable-region-focusable)
      tabIndex={0}
      aria-label="Table"
    >
      <table {...props} />
    </section>
  );
}

export function getMDXComponents(components?: MDXComponents) {
  return {
    ...defaultMdxComponents,
    Step,
    Steps,
    Tab,
    Tabs,
    TypeTable,
    table: Table,
    ...components,
  } satisfies MDXComponents;
}

export const useMDXComponents = getMDXComponents;

declare global {
  type MDXProvidedComponents = ReturnType<typeof getMDXComponents>;
}
