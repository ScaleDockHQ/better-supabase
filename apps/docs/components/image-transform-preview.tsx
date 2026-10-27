"use client";

import { storageImageUrl } from "better-supabase/storage";
import { useId, useState } from "react";

type Resize = "cover" | "contain" | "fill";

const RESIZES: readonly Resize[] = ["cover", "contain", "fill"];

const OBJECT_PATH = "/storage/v1/object/public/";

const projectUrl = (src: string): string | undefined => {
  try {
    const url = new URL(src);

    return url.pathname.startsWith(OBJECT_PATH) ? url.origin : undefined;
  } catch {
    return;
  }
};

const isResize = (value: string): value is Resize =>
  RESIZES.some((resize) => resize === value);

function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);

  return (
    <button
      type="button"
      className="rounded-md border px-2 py-1 text-xs transition-colors hover:bg-fd-accent"
      aria-label={label}
      onClick={() => {
        void navigator.clipboard.writeText(text).then(() => {
          setCopied(true);
          setTimeout(() => {
            setCopied(false);
          }, 1500);

          return true;
        });
      }}
    >
      {copied ? "Copied" : "Copy"}
    </button>
  );
}

function NumberField(props: {
  label: string;
  value: number;
  min: number;
  max: number;
  onChange: (value: number) => void;
}) {
  const id = useId();

  return (
    <label htmlFor={id} className="flex flex-col gap-1 text-xs">
      <span className="text-fd-muted-foreground">{props.label}</span>
      <input
        id={id}
        type="number"
        className="rounded-md border bg-fd-background px-2 py-1 text-sm tabular-nums"
        min={props.min}
        max={props.max}
        value={props.value}
        onChange={(event) => {
          const value = event.currentTarget.valueAsNumber;

          if (Number.isFinite(value)) {
            props.onChange(value);
          }
        }}
      />
    </label>
  );
}

function Preview({ src, alt }: { src: string; alt: string }) {
  const [state, setState] = useState<"loading" | "loaded" | "error">("loading");

  const [attempt, setAttempt] = useState(0);

  if (state === "error") {
    return (
      <div className="flex min-h-32 flex-col items-start justify-center gap-2 text-sm">
        <p className="text-fd-muted-foreground">
          Storage did not return an image. Transformations need a paid plan, and
          a local stack needs <code>[storage.image_transformation]</code> turned
          on.
        </p>
        <button
          type="button"
          className="rounded-md border px-2 py-1 text-xs transition-colors hover:bg-fd-accent"
          onClick={() => {
            setState("loading");
            setAttempt((value) => value + 1);
          }}
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="relative min-h-32">
      {state === "loading" ? (
        <div
          className="absolute inset-0 animate-pulse rounded-md bg-fd-muted motion-reduce:animate-none"
          aria-hidden
        />
      ) : null}
      {/* oxlint-disable-next-line react-doctor/nextjs-no-img-element, nextjs/no-img-element -- the preview shows Storage's own output, not the Next.js optimizer's */}
      <img
        key={attempt}
        src={src}
        alt={alt}
        className="max-h-80 max-w-full rounded-md"
        onLoad={() => {
          setState("loaded");
        }}
        onError={() => {
          setState("error");
        }}
      />
    </div>
  );
}

/** Builds a Storage image transformation URL for a public object and shows it. */
export function ImageTransformPreview() {
  const urlId = useId();
  const resizeId = useId();
  const [src, setSrc] = useState("");
  const [width, setWidth] = useState(400);
  const [height, setHeight] = useState(300);
  const [resize, setResize] = useState<Resize>("cover");
  const [quality, setQuality] = useState(80);

  const project = projectUrl(src.trim());

  const rendered =
    project === undefined
      ? undefined
      : storageImageUrl({ url: project, resize })(src.trim(), {
          width,
          height,
          quality,
        });

  const snippet = `variants: {\n  preview: { width: ${String(width)}, height: ${String(height)}, resize: "${resize}", quality: ${String(quality)} },\n},`;

  return (
    <div className="not-prose my-6 flex flex-col gap-4 rounded-lg border bg-fd-card p-4">
      <label htmlFor={urlId} className="flex flex-col gap-1 text-xs">
        <span className="text-fd-muted-foreground">Public object URL</span>
        <input
          id={urlId}
          type="url"
          className="rounded-md border bg-fd-background px-2 py-1 text-sm"
          placeholder="https://<project>.supabase.co/storage/v1/object/public/avatars/u1/avatar-1.png"
          value={src}
          onChange={(event) => {
            setSrc(event.currentTarget.value);
          }}
        />
      </label>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <NumberField
          label="Width"
          value={width}
          min={1}
          max={2500}
          onChange={setWidth}
        />
        <NumberField
          label="Height"
          value={height}
          min={1}
          max={2500}
          onChange={setHeight}
        />
        <label htmlFor={resizeId} className="flex flex-col gap-1 text-xs">
          <span className="text-fd-muted-foreground">Resize</span>
          <select
            id={resizeId}
            className="rounded-md border bg-fd-background px-2 py-1 text-sm"
            value={resize}
            onChange={(event) => {
              const { value } = event.currentTarget;

              if (isResize(value)) {
                setResize(value);
              }
            }}
          >
            {RESIZES.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </label>
        <NumberField
          label="Quality"
          value={quality}
          min={20}
          max={100}
          onChange={setQuality}
        />
      </div>

      {rendered === undefined ? (
        <p className="text-sm text-fd-muted-foreground">
          {src.trim() === "" ? (
            "Paste the URL of an image in a public bucket to preview the crop. It only reads public URLs, so it needs no keys."
          ) : (
            <>
              That is not a public Storage object URL. It needs the{" "}
              <code>{OBJECT_PATH}</code> path.
            </>
          )}
        </p>
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="flex flex-col gap-2">
              <span className="text-xs text-fd-muted-foreground">Original</span>
              <Preview key={src} src={src.trim()} alt="Original" />
            </div>
            <div className="flex flex-col gap-2">
              <span className="text-xs text-fd-muted-foreground">
                {`${String(width)} × ${String(height)}, ${resize}`}
              </span>
              <Preview key={rendered} src={rendered} alt="Transformed" />
            </div>
          </div>
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-2">
              <span className="text-xs text-fd-muted-foreground">URL</span>
              <CopyButton text={rendered} label="Copy the URL" />
            </div>
            <code className="overflow-x-auto rounded-md bg-fd-muted p-2 text-xs break-all">
              {rendered}
            </code>
          </div>
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-2">
              <span className="text-xs text-fd-muted-foreground">
                Bucket variant
              </span>
              <CopyButton text={snippet} label="Copy the variant" />
            </div>
            <pre className="overflow-x-auto rounded-md bg-fd-muted p-2 text-xs">
              {snippet}
            </pre>
          </div>
        </>
      )}
    </div>
  );
}
