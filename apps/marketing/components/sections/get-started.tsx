import { Section } from "@/components/sections/section";
import { getStartedSteps } from "@/lib/home";

export function GetStarted() {
  return (
    <Section
      id="get-started"
      eyebrow="Get started"
      title="From install to typed queries in four steps"
    >
      <ol className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {getStartedSteps.map((step, index) => (
          <li
            key={step.title}
            className="border-border bg-card flex flex-col gap-2 rounded-xl border p-5"
          >
            <span className="text-brand font-mono text-xs">
              {String(index + 1).padStart(2, "0")}
            </span>
            <span className="text-sm font-semibold">{step.title}</span>
            <span className="text-muted-foreground text-sm leading-6">
              {step.body}
            </span>
          </li>
        ))}
      </ol>
    </Section>
  );
}
