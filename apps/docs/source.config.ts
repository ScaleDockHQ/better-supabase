import { rehypeCodeDefaultOptions } from "fumadocs-core/mdx-plugins";
import { defineConfig } from "fumadocs-mdx/config";
import { transformerTwoslash } from "fumadocs-twoslash";
import { remarkAutoTypeTable } from "fumadocs-typescript";

export default defineConfig({
  mdxOptions: {
    // `remarkStringify` keeps the generated tables in the processed Markdown
    // that /llms.txt and the .md routes serve.
    remarkPlugins: [
      [
        remarkAutoTypeTable,
        { remarkStringify: true, options: { basePath: "../.." } },
      ],
    ],
    rehypeCodeOptions: {
      // github-light's orange and red are under 4.5:1 on the code background.
      themes: { light: "github-light-high-contrast", dark: "github-dark" },
      langs: ["ts", "tsx", "sql", "bash", "json", "yaml", "toml"],
      transformers: [
        ...(rehypeCodeDefaultOptions.transformers ?? []),
        transformerTwoslash(),
      ],
    },
  },
});
