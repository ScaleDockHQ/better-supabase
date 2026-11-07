import { DocumentRegister } from "@/features/drive/components/document-register";
import { getDocumentRegister } from "@/features/drive/drive-queries";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
export async function DocumentRegisterSection() {
  return <DocumentRegister state={await getDocumentRegister()} />;
}
