import { Panel, PanelSkeleton } from '@/components/ui/panel';

import { getSimilarNotes } from '../note-queries';

export async function SimilarNotes() {
  const result = await getSimilarNotes();
  if (!result) return null;
  return (
    <Panel>
      <h2>Notes like “{result.source.body}”</h2>
      <ol data-testid="similar-notes">
        {result.similar.map((note) => (
          <li key={note.id}>
            {note.body} <small>{note.kind}</small>
          </li>
        ))}
      </ol>
    </Panel>
  );
}

export function SimilarNotesSkeleton() {
  return <PanelSkeleton />;
}
