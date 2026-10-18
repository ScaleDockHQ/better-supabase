import { ChevronRightIcon } from "lucide-react";

import { JsonLd } from "@/components/site/json-ld";
import { SiteLink } from "@/components/site/site-link";
import { site } from "@/lib/site";
import { absoluteUrl, breadcrumbList, type Crumb } from "@/lib/structured-data";

/** The trail above a catalog page, with the same trail as a BreadcrumbList. */
export function Breadcrumbs({ items }: { items: readonly Crumb[] }) {
  return (
    <>
      <nav aria-label="Breadcrumb">
        <ol className="flex flex-wrap items-center gap-1.5 text-sm text-muted-foreground">
          {items.map((item, index) => {
            const last = index === items.length - 1;

            return (
              <li key={item.href} className="flex items-center gap-1.5">
                {last ? (
                  <span aria-current="page" className="text-foreground">
                    {item.name}
                  </span>
                ) : (
                  <>
                    <SiteLink
                      href={item.href}
                      className="transition-colors hover:text-foreground"
                    >
                      {item.name}
                    </SiteLink>
                    <ChevronRightIcon aria-hidden="true" className="size-3.5" />
                  </>
                )}
              </li>
            );
          })}
        </ol>
      </nav>
      <JsonLd
        data={breadcrumbList(
          items.map((item) => ({
            ...item,
            href: absoluteUrl(item.href, site.url),
          })),
        )}
      />
    </>
  );
}
