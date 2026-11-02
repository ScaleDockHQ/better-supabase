import { Frame, FramePanel } from "@/components/reui/frame";
import { Section } from "@/components/sections/section";
import { CopyCommand } from "@/components/site/copy-command";
import { LinkButton } from "@/components/site/link-button";
import { agentTools } from "@/lib/home";

export function AgentsSection() {
  return (
    <Section
      id="agents"
      eyebrow="For coding agents"
      title="The same CLI, safe to hand to an agent"
      description="Agents read the catalog, run doctor and write migrations through the commands you use. Anything that writes files or touches data waits for the user's consent."
    >
      <ul className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        {agentTools.map((tool) => (
          <li key={tool.title}>
            <Frame className="h-full">
              <FramePanel className="flex h-full flex-col gap-4">
                <div className="flex flex-col gap-1">
                  <h3 className="text-base font-semibold tracking-tight">
                    {tool.title}
                  </h3>
                  <p className="text-sm leading-6 text-pretty text-muted-foreground">
                    {tool.body}
                  </p>
                </div>
                <div className="mt-auto flex flex-col items-start gap-3">
                  <CopyCommand command={tool.code} />
                  <LinkButton variant="link" href={tool.href}>
                    Read the docs
                  </LinkButton>
                </div>
              </FramePanel>
            </Frame>
          </li>
        ))}
      </ul>
    </Section>
  );
}
