/** Splits a `data:<mime>;base64,<data>` URL into its parts. Returns null if
 * the string isn't a base64 data URL. */
export function parseDataUrl(dataUrl: string): { mimeType: string; data: string } | null {
  const match = /^data:([^;]+);base64,([\s\S]+)$/.exec(dataUrl);
  if (!match) return null;
  return { mimeType: match[1], data: match[2] };
}
