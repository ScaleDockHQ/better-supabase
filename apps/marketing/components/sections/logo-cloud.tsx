import { Section } from "@/components/sections/section";
import { BrandLogo } from "@/components/site/brand-icons";
import { SiteLink } from "@/components/site/site-link";
import {
  integrationCounts,
  integrationGroups,
  integrationsIn,
} from "@/lib/integrations";

/** Every supported framework, runtime and SDK, each linking to its docs page. */
export function LogoCloud() {
  return (
    <Section
      id="frameworks"
      eyebrow="Frameworks"
      title="Works where your code runs"
      description="Adapters build a per-request client for the caller, so the same repository API works in pages, routes, procedures and functions. Runtime entries import no Node built-ins, so they run on every WinterTC runtime."
    >
      <div className="flex flex-col items-center gap-8">
        <p className="text-sm text-muted-foreground tabular-nums">
          {integrationCounts()}
        </p>
        {integrationGroups.map((group) => {
          const headingId = `integrations-${group.toLowerCase().replaceAll(" ", "-")}`;

          return (
            <div
              key={group}
              className="flex w-full flex-col items-center gap-4"
            >
              <h3
                id={headingId}
                className="text-xs font-semibold tracking-wide text-muted-foreground uppercase"
              >
                {group}
              </h3>
              <ul
                aria-labelledby={headingId}
                className="flex max-w-4xl flex-wrap justify-center gap-x-2 gap-y-4"
              >
                {integrationsIn(group).map((integration) => (
                  <li key={integration.name}>
                    <SiteLink
                      href={integration.href}
                      className="flex w-24 flex-col items-center gap-2 rounded-md p-2 text-muted-foreground transition-colors outline-none hover:text-foreground focus-visible:text-foreground focus-visible:ring-3 focus-visible:ring-ring/50"
                    >
                      <BrandLogo mark={integration.mark} className="size-7" />
                      <span className="text-center text-xs leading-4">
                        {integration.name}
                      </span>
                    </SiteLink>
                  </li>
                ))}
              </ul>
            </div>
          );
        })}
      </div>
    </Section>
  );
}
