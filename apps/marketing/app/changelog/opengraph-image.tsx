import { OgImage, ogSize } from '@/lib/og';

export const alt = 'Changelog';
export const size = ogSize;
export const contentType = 'image/png';

export default function Image() {
  return OgImage({
    title: 'Changelog',
    description: 'What shipped in better-supabase.',
  });
}
