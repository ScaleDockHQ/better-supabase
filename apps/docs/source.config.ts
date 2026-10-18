import { rehypeCodeDefaultOptions } from "fumadocs-core/mdx-plugins";
import { replaceSource } from "fumadocs-core/mdx-plugins/stringifier";
import { defineConfig } from "fumadocs-mdx/config";
import { remarkAutoTypeTable } from "fumadocs-typescript";

type MdastFile = Parameters<typeof replaceSource>[0];

type MdastNode = Parameters<typeof replaceSource>[1];

function dropTitles(node: MdastNode, file: MdastFile): void {
  if (!("children" in node)) {
    return;
  }

  for (let index = node.children.length - 1; index >= 0; index--) {
    const child = node.children[index];

    if (child === undefined) {
      continue;
    }

    if (child.type === "heading" && child.depth === 1) {
      // The processed Markdown is cut from the source, so blank it there too.
      replaceSource(file, child, "");
      node.children.splice(index, 1);
    } else {
      dropTitles(child, file);
    }
  }
}

/**
 * Drops `# h1` headings, including those in an `<include>`d file (a nested
 * root), since the page title comes from the frontmatter.
 */
function remarkDropTitle() {
  return dropTitles;
}

export default defineConfig({
  mdxOptions: {
    // `remarkStringify` keeps the generated tables in the processed Markdown
    // that /llms.txt and the .md routes serve.
    remarkPlugins: [
      // `changelog.mdx` includes the root CHANGELOG.md, which opens with one.
      remarkDropTitle,
      [
        remarkAutoTypeTable,
        { remarkStringify: true, options: { basePath: "../.." } },
      ],
    ],
    rehypeCodeOptions: {
      // github-light's orange and red are under 4.5:1 on the code background.
      themes: { light: "github-light-high-contrast", dark: "github-dark" },
      langs: ["ts", "tsx", "sql", "bash", "json", "yaml", "toml"],
      transformers: rehypeCodeDefaultOptions.transformers ?? [],
    },
  },
});
