import {
  BoxIcon,
  ClockIcon,
  GitBranchIcon,
  HandIcon,
  PlayIcon,
  RepeatIcon,
  SparklesIcon,
  SplitIcon,
  SquareFunctionIcon,
  UserCheckIcon,
  WorkflowIcon,
} from "lucide-react";

/** The icon of a node kind, for the canvas and the run trace. */
export function KindIcon({
  kind,
  className,
}: {
  kind: string;
  className?: string;
}) {
  switch (kind) {
    case "trigger": {
      return <PlayIcon className={className} />;
    }

    case "step": {
      return <SquareFunctionIcon className={className} />;
    }

    case "sleep": {
      return <ClockIcon className={className} />;
    }

    case "approval": {
      return <HandIcon className={className} />;
    }

    case "condition": {
      return <GitBranchIcon className={className} />;
    }

    case "loop": {
      return <RepeatIcon className={className} />;
    }

    case "parallel": {
      return <SplitIcon className={className} />;
    }

    case "human-task": {
      return <UserCheckIcon className={className} />;
    }

    case "ai-step": {
      return <SparklesIcon className={className} />;
    }

    case "sub-workflow": {
      return <WorkflowIcon className={className} />;
    }

    default: {
      return <BoxIcon className={className} />;
    }
  }
}
