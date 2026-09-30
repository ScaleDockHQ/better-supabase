import { cn } from "@/lib/utils";

export function LogoMark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden="true"
      className={cn("text-brand size-5", className)}
      fill="none"
    >
      <path
        d="M13.2 2.4 4.4 13.5c-.5.6 0 1.5.8 1.5h6.3l-.7 6.6c-.1.8.9 1.2 1.4.6l8.8-11.1c.5-.6 0-1.5-.8-1.5h-6.3l.7-6.6c.1-.8-.9-1.2-1.4-.6Z"
        fill="currentColor"
      />
    </svg>
  );
}
