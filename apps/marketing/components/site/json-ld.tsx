/**
 * A schema.org graph as `application/ld+json`. `<` is escaped so no string can
 * close the tag.
 */
export function JsonLd({ data }: { data: { readonly "@context": string } }) {
  return (
    <script
      type="application/ld+json"
      // The data is built from the static catalog and site config, and escaped above.
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(data).replaceAll("<", String.raw`\u003c`),
      }}
    />
  );
}
