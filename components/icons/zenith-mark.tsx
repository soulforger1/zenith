/** The app's mark: two overlapping peaks, the taller one reaching the top of
 * the frame — a literal "zenith" (highest point reached). Uses `currentColor`
 * so it inherits whatever text color its container sets (matches how the
 * sidebar badge already works: `bg-primary/15 text-primary`). */
export function ZenithMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg" className={className}>
      <path d="M6 38 L20 12 L34 38 Z" fill="currentColor" opacity="0.45" />
      <path d="M16 40 L30 8 L44 40 Z" fill="currentColor" />
    </svg>
  );
}
