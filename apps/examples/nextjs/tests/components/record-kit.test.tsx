import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { RecordDetailFrame } from "@/components/record-detail/record-detail-frame";
import { RecordSectionSkeleton } from "@/components/record-detail/record-section-states";
import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

describe("record kit", () => {
  it("renders the list skeleton with a toolbar and the asked rows", () => {
    const html = renderToStaticMarkup(<RecordListSkeleton rows={3} />);

    expect(html).toContain('aria-busy="true"');
    expect(html.match(/h-9 w-full/g)).toHaveLength(3);
  });

  it("renders the detail head, the sections and the aside", () => {
    const html = renderToStaticMarkup(
      <RecordDetailFrame
        title="Road Runner Inc"
        description="Customer since 2024"
        aside={<p>Aside</p>}
      >
        <p>Main</p>
      </RecordDetailFrame>,
    );

    expect(html).toContain("<h1");
    expect(html).toContain("Road Runner Inc");
    expect(html).toContain("Customer since 2024");
    expect(html).toContain("Aside");
    expect(html).toContain("Main");
  });

  it("omits the aside column when there is none", () => {
    const html = renderToStaticMarkup(
      <RecordDetailFrame title="Solo">
        <p>Main</p>
      </RecordDetailFrame>,
    );

    expect(html.match(/flex flex-col gap-6/g)).toHaveLength(1);
  });

  it("renders a section skeleton", () => {
    expect(renderToStaticMarkup(<RecordSectionSkeleton rows={2} />)).toContain(
      'aria-busy="true"',
    );
  });
});
