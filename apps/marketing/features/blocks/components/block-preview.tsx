import type { ReactNode } from "react";

import { cn } from "@/lib/utils";

import { type CategoryStyle, categoryStyle } from "../categories";

/*
 * Illustrations, not product UI: each scene sketches what a category's blocks
 * put on screen. They are aria-hidden and use the 2xs to 4xs text sizes, which the ReUI rules
 * allow for illustrative mini UI only.
 */

function Window({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex flex-col gap-2 rounded-lg border border-border bg-card p-3 text-2xs leading-4 text-card-foreground shadow-xs",
        className,
      )}
    >
      {children}
    </div>
  );
}

function Line({ className }: { className?: string }) {
  return (
    <span className={cn("block h-1.5 rounded-full bg-muted", className)} />
  );
}

function Avatar({ tone, label }: { tone: CategoryStyle; label: string }) {
  return (
    <span
      className={cn(
        "flex size-5 shrink-0 items-center justify-center rounded-full text-3xs font-semibold text-white",
        tone.solid,
      )}
    >
      {label}
    </span>
  );
}

const FOUNDATION_ROWS = [
  ["acme", "owner", "2m"],
  ["globex", "admin", "1h"],
  ["initech", "member", "3d"],
] as const;

function FoundationScene({ tone }: { tone: CategoryStyle }) {
  return (
    <Window className="w-full">
      <div className="flex items-center justify-between font-medium">
        <span>organizations</span>
        <span className={cn("rounded px-1.5", tone.soft, tone.text)}>
          RLS on
        </span>
      </div>
      <div className="grid grid-cols-3 gap-x-2 gap-y-1.5 font-mono text-muted-foreground">
        <span>tenant</span>
        <span>role</span>
        <span>updated_at</span>
        {FOUNDATION_ROWS.map(([tenant, role, at]) => (
          <span key={tenant} className="contents">
            <span className="text-foreground">{tenant}</span>
            <span>{role}</span>
            <span>{at} ago</span>
          </span>
        ))}
      </div>
    </Window>
  );
}

const OPERATIONS_BARS = [
  "h-[40%]",
  "h-[65%]",
  "h-[52%]",
  "h-[80%]",
  "h-[70%]",
  "h-[92%]",
  "h-[60%]",
  "h-[75%]",
] as const;

function OperationsScene({ tone }: { tone: CategoryStyle }) {
  return (
    <Window className="w-full">
      <div className="flex items-center justify-between font-medium">
        <span>Signups this week</span>
        <span className={tone.text}>+18%</span>
      </div>
      <div className="flex h-14 items-end gap-1">
        {OPERATIONS_BARS.map((height, index) => (
          <span
            key={height}
            className={cn(
              "flex-1 rounded-sm",
              height,
              index === 5 ? tone.solid : tone.soft,
            )}
          />
        ))}
      </div>
      <div className="flex items-center gap-1.5 text-muted-foreground">
        <span className={cn("size-1.5 rounded-full", tone.solid)} />
        flag new-onboarding at 25%
      </div>
    </Window>
  );
}

const PLATFORM_JOBS = [
  ["send-invoice", "done"],
  ["sync-crm", "running"],
  ["webhook.retry", "queued"],
] as const;

function PlatformScene({ tone }: { tone: CategoryStyle }) {
  return (
    <Window className="w-full">
      <div className="font-medium">PLATFORM_JOBS</div>
      {PLATFORM_JOBS.map(([name, status]) => (
        <div key={name} className="flex items-center justify-between gap-2">
          <span className="font-mono">{name}</span>
          <span
            className={cn(
              "rounded px-1.5",
              status === "queued"
                ? "bg-muted text-muted-foreground"
                : [tone.soft, tone.text],
            )}
          >
            {status}
          </span>
        </div>
      ))}
      <div className="flex items-center gap-1.5 font-mono text-muted-foreground">
        <span className={cn("size-1.5 rounded-full", tone.solid)} />
        sk_live_••••4f2a
      </div>
    </Window>
  );
}

const BILLING_LINES = [
  ["Pro plan", "€49.00"],
  ["Seats × 3", "€27.00"],
  ["Usage", "€4.20"],
] as const;

function BillingScene({ tone }: { tone: CategoryStyle }) {
  return (
    <Window className="w-full">
      <div className="flex items-center justify-between font-medium">
        <span>Invoice INV-0042</span>
        <span className={cn("rounded px-1.5", tone.soft, tone.text)}>paid</span>
      </div>
      {BILLING_LINES.map(([label, amount]) => (
        <div key={label} className="flex justify-between text-muted-foreground">
          <span>{label}</span>
          <span className="tabular-nums">{amount}</span>
        </div>
      ))}
      <div className="flex justify-between border-t border-border pt-1.5 font-semibold">
        <span>Total</span>
        <span className="tabular-nums">€80.20</span>
      </div>
    </Window>
  );
}

function AiScene({ tone }: { tone: CategoryStyle }) {
  return (
    <Window className="w-full">
      <div className="ml-auto max-w-[75%] rounded-md bg-muted px-2 py-1">
        Which deals close this month?
      </div>
      <div className="flex gap-1.5">
        <span
          className={cn(
            "flex size-4 shrink-0 items-center justify-center rounded-full text-4xs font-bold text-white",
            tone.solid,
          )}
        >
          AI
        </span>
        <div
          className={cn("flex flex-col gap-1 rounded-md px-2 py-1", tone.soft)}
        >
          <span>3 deals, €42k in total.</span>
          <Line className="w-24 bg-foreground/15" />
          <Line className="w-16 bg-foreground/15" />
        </div>
      </div>
    </Window>
  );
}

function CollaborationScene({ tone }: { tone: CategoryStyle }) {
  return (
    <Window className="w-full">
      <div className="flex gap-1.5">
        <Avatar tone={tone} label="A" />
        <div className="flex flex-col gap-0.5">
          <span className="font-medium">Ada</span>
          <span className="text-muted-foreground">
            Can you check the totals, <span className={tone.text}>@Sam</span>?
          </span>
        </div>
      </div>
      <div className="flex gap-1.5 pl-6">
        <Avatar tone={tone} label="S" />
        <div className="flex flex-col gap-0.5">
          <span className="font-medium">Sam</span>
          <span className="text-muted-foreground">Fixed, thanks.</span>
        </div>
      </div>
      <div className="flex gap-1 pl-6">
        <span className={cn("rounded-full px-1.5", tone.soft, tone.text)}>
          +2
        </span>
        <span className="rounded-full bg-muted px-1.5">Resolved</span>
      </div>
    </Window>
  );
}

const WORK_COLUMNS = [
  { title: "To do", cards: 2 },
  { title: "Doing", cards: 1 },
  { title: "Done", cards: 2 },
];

function WorkScene({ tone }: { tone: CategoryStyle }) {
  return (
    <div className="grid w-full grid-cols-3 gap-1.5">
      {WORK_COLUMNS.map((column, columnIndex) => (
        <Window key={column.title} className="gap-1.5 p-2">
          <span className="font-medium">{column.title}</span>
          {Array.from({ length: column.cards }, (_, index) => (
            <span
              key={`${column.title}-${String(index)}`}
              className="flex flex-col gap-1 rounded border border-border bg-background p-1.5"
            >
              <Line className="w-full" />
              <span
                className={cn(
                  "h-1.5 w-8 rounded-full",
                  columnIndex === 1 ? tone.solid : tone.soft,
                )}
              />
            </span>
          ))}
        </Window>
      ))}
    </div>
  );
}

function SchedulingScene({ tone }: { tone: CategoryStyle }) {
  const booked = new Set([3, 9, 10, 16, 23]);

  return (
    <Window className="w-full">
      <div className="flex items-center justify-between font-medium">
        <span>October</span>
        <span className="text-muted-foreground">Week 42</span>
      </div>
      <div className="grid grid-cols-7 gap-1 text-center text-muted-foreground">
        {Array.from({ length: 28 }, (_, index) => (
          <span
            key={`day-${String(index)}`}
            className={cn(
              "rounded py-0.5 tabular-nums",
              booked.has(index) && [tone.solid, "text-white"],
              index === 17 && [tone.soft, tone.text],
            )}
          >
            {index + 1}
          </span>
        ))}
      </div>
    </Window>
  );
}

function ContentScene({ tone }: { tone: CategoryStyle }) {
  return (
    <Window className="w-full">
      <div className="flex items-center gap-1 border-b border-border pb-1.5 text-muted-foreground">
        <span className="rounded bg-muted px-1 font-bold">B</span>
        <span className="rounded bg-muted px-1 italic">I</span>
        <span className="rounded bg-muted px-1">H1</span>
        <span className={cn("ml-auto rounded px-1.5", tone.soft, tone.text)}>
          v12
        </span>
      </div>
      <span className="font-semibold">Q4 launch plan</span>
      <Line className="w-full" />
      <Line className="w-5/6" />
      <div className="flex items-center gap-1.5">
        <span className={cn("h-6 w-8 rounded", tone.soft)} />
        <Line className="w-1/2" />
      </div>
    </Window>
  );
}

const CRM_STAGES = [
  ["Lead", 24, "w-[72%]"],
  ["Qualified", 12, "w-[36%]"],
  ["Proposal", 7, "w-[21%]"],
  ["Won", 4, "w-[12%]"],
] as const;

function CrmScene({ tone }: { tone: CategoryStyle }) {
  return (
    <Window className="w-full">
      <div className="font-medium">Pipeline</div>
      {CRM_STAGES.map(([stage, count, width], index) => (
        <div key={stage} className="flex items-center gap-2">
          <span className="w-14 text-muted-foreground">{stage}</span>
          <span
            className={cn(
              "h-2 rounded-full",
              width,
              index === CRM_STAGES.length - 1 ? tone.solid : tone.soft,
            )}
          />
          <span className="tabular-nums">{count}</span>
        </div>
      ))}
    </Window>
  );
}

function Scene({ tone }: { tone: CategoryStyle }) {
  switch (tone.name) {
    case "Identity & access":
    case "Tenancy & accounts": {
      return <FoundationScene tone={tone} />;
    }

    case "Collaboration":
    case "Notifications & messaging": {
      return <CollaborationScene tone={tone} />;
    }

    case "Growth & engagement":
    case "Admin & compliance": {
      return <OperationsScene tone={tone} />;
    }

    case "Automation":
    case "Developer platform":
    case "Database primitives":
    case "App tables": {
      return <PlatformScene tone={tone} />;
    }

    case "Billing & commerce": {
      return <BillingScene tone={tone} />;
    }

    case "AI": {
      return <AiScene tone={tone} />;
    }

    case "Work management":
    case "People": {
      return <WorkScene tone={tone} />;
    }

    case "Scheduling": {
      return <SchedulingScene tone={tone} />;
    }

    case "Content & files": {
      return <ContentScene tone={tone} />;
    }

    case "CRM & sales": {
      return <CrmScene tone={tone} />;
    }

    default: {
      const unknown: never = tone.name;

      return unknown;
    }
  }
}

/** A category's tinted, dotted surface that a scene or screenshot sits on. */
export function PreviewSurface({
  category,
  size = "default",
  className,
  children,
}: {
  category: string;
  size?: "default" | "lg";
  className?: string | undefined;
  children: ReactNode;
}) {
  const tone = categoryStyle(category);

  return (
    <div
      className={cn(
        "relative flex items-center justify-center overflow-hidden",
        "before:pointer-events-none before:absolute before:inset-0 before:bg-dots before:opacity-7",
        tone.tint,
        size === "lg" ? "aspect-[16/9] p-8 sm:p-12" : "aspect-[16/10] p-5",
        className,
      )}
    >
      {children}
    </div>
  );
}

/**
 * A category's mini UI on its surface. `size="lg"` is the block page hero;
 * the default fits a catalog tile.
 */
export function BlockPreview({
  category,
  size = "default",
  className,
}: {
  category: string;
  size?: "default" | "lg";
  className?: string | undefined;
}) {
  return (
    <PreviewSurface
      category={category}
      size={size}
      className={cn("select-none", className)}
    >
      <div
        aria-hidden="true"
        className={cn(
          "relative w-full",
          size === "lg" ? "max-w-sm" : "max-w-[15rem]",
        )}
      >
        <Scene tone={categoryStyle(category)} />
      </div>
    </PreviewSurface>
  );
}
