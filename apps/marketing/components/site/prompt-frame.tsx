import type { ReactElement, ReactNode } from "react";

import {
  Frame,
  FrameDescription,
  FrameHeader,
  FramePanel,
  FrameTitle,
} from "@/components/reui/frame";
import { CopyButton } from "@/components/site/copy-button";

/**
 * A prompt for a coding agent in a scrolling panel, with a copy button.
 * `children` sit in the header next to the copy button, for controls that
 * change the prompt. `testId` marks the frame, and `<testId>-text` the text.
 */
export function PromptFrame({
  title,
  description,
  prompt,
  copyLabel,
  testId,
  children,
}: {
  title: string;
  description: ReactNode;
  prompt: string;
  copyLabel: string;
  testId: string;
  children?: ReactNode;
}): ReactElement {
  return (
    <Frame data-testid={testId}>
      <FrameHeader className="flex-row flex-wrap items-start justify-between gap-2">
        <div className="flex min-w-0 flex-1 flex-col gap-1">
          <FrameTitle>{title}</FrameTitle>
          <FrameDescription>{description}</FrameDescription>
        </div>
        <div className="flex items-center gap-2">
          {children}
          <CopyButton text={prompt} label={copyLabel} />
        </div>
      </FrameHeader>
      <FramePanel className="p-0">
        <section
          aria-label={title}
          // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- a scrolling region needs keyboard focus (axe scrollable-region-focusable)
          tabIndex={0}
          className="max-h-60 overflow-auto outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
        >
          <pre className="p-4 font-mono text-code leading-6 break-words whitespace-pre-wrap">
            <code data-testid={`${testId}-text`}>{prompt}</code>
          </pre>
        </section>
      </FramePanel>
    </Frame>
  );
}
