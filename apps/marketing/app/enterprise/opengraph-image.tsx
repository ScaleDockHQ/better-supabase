import { OgImage, ogSize } from '@/lib/og';

export const alt = 'Enterprise';
export const size = ogSize;
export const contentType = 'image/png';

export default function Image() {
  return OgImage({
    title: 'Enterprise',
    description: 'Support, architecture reviews and migrations.',
  });
}
