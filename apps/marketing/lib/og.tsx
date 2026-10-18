import { ImageResponse } from "next/og";

import { site } from "./site";

export const ogSize = { width: 1200, height: 630 };

const MAX_DESCRIPTION = 180;

const clamp = (text: string): string =>
  text.length > MAX_DESCRIPTION
    ? `${text.slice(0, MAX_DESCRIPTION).replace(/\s+\S*$/, "")}...`
    : text;

export function OgImage({
  title,
  description,
  eyebrow = site.name,
}: {
  title: string;
  description: string;
  /** The line above the title, such as "Block / Collaboration". */
  eyebrow?: string | undefined;
}) {
  return new ImageResponse(
    <div
      style={{
        height: "100%",
        width: "100%",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        padding: 80,
        background: "#0a0a0a",
        color: "#fafafa",
      }}
    >
      <div style={{ fontSize: 28, color: "#3ecf8e", marginBottom: 16 }}>
        {eyebrow}
      </div>
      <div style={{ fontSize: 64, fontWeight: 600, lineHeight: 1.1 }}>
        {title}
      </div>
      <div style={{ fontSize: 28, opacity: 0.7, marginTop: 24 }}>
        {clamp(description)}
      </div>
    </div>,
    { ...ogSize },
  );
}
