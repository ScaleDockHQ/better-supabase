import { MinusIcon, CheckIcon } from "lucide-react";

import { Frame, FramePanel } from "@/components/reui/frame";
import { Section } from "@/components/sections/section";
import { beforeAfter } from "@/lib/home";

function Column({
  title,
  items,
  done,
}: {
  title: string;
  items: readonly string[];
  done: boolean;
}) {
  const Icon = done ? CheckIcon : MinusIcon;

  return (
    <Frame className="h-full">
      <FramePanel className="flex h-full flex-col gap-4">
        <h3 className="text-sm font-semibold">{title}</h3>
        <ul className="flex flex-col gap-3">
          {items.map((item) => (
            <li key={item} className="flex gap-3 text-sm leading-6">
              <Icon
                aria-hidden="true"
                className={
                  done
                    ? "mt-1 size-4 shrink-0 text-brand"
                    : "mt-1 size-4 shrink-0 text-muted-foreground"
                }
              />
              <span className={done ? undefined : "text-muted-foreground"}>
                {item}
              </span>
            </li>
          ))}
        </ul>
      </FramePanel>
    </Frame>
  );
}

export function BeforeAfter() {
  return (
    <Section
      id="before-after"
      eyebrow="Before and after"
      title="The parts every product shares, written once"
      description="The work that is yours stays yours: your tables, your product rules and your screens."
    >
      <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
        <Column
          title="Without blocks"
          items={beforeAfter.before}
          done={false}
        />
        <Column title="With blocks" items={beforeAfter.after} done />
      </div>
    </Section>
  );
}
