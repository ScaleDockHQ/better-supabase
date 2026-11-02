import { CodeBlock } from "@/components/code-block";
import { Frame, FramePanel } from "@/components/reui/frame";
import { Section } from "@/components/sections/section";
import { howItWorks } from "@/lib/home";

export function HowItWorks() {
  return (
    <Section
      id="how-it-works"
      eyebrow="How it works"
      title="Your tables, a few tags, SQL from blocks, a typed client"
      description="Nothing sits between you and the database. Every step produces files you can read, and each one works without the others."
    >
      <ol className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {howItWorks.map((step, index) => (
          <li key={step.title}>
            <Frame className="h-full">
              <FramePanel className="flex h-full flex-col gap-4">
                <div className="flex flex-col gap-1">
                  <p className="text-xs font-semibold text-muted-foreground tabular-nums">
                    Step {index + 1}
                  </p>
                  <h3 className="text-base font-semibold tracking-tight">
                    {step.title}
                  </h3>
                  <p className="text-sm leading-6 text-pretty text-muted-foreground">
                    {step.body}
                  </p>
                </div>
                <CodeBlock snippet={step.snippet} className="mt-auto" />
              </FramePanel>
            </Frame>
          </li>
        ))}
      </ol>
    </Section>
  );
}
