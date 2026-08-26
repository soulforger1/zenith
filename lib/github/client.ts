import "server-only";

// Curated (not exhaustive) signals used to seed the AI repo-summary prompt —
// capped so a "Sync" stays a small, bounded one-off cost, never a full
// source dump. See lib/ai/prompts.ts:summarizeRepoContext.
const README_CHAR_LIMIT = 6000;
const PACKAGE_JSON_CHAR_LIMIT = 2000;
const TREE_ENTRY_LIMIT = 60;

export type RepoSnapshot = {
  fullName: string;
  description: string | null;
  language: string | null;
  topics: string[];
  readme: string | null;
  packageJson: string | null;
  tree: string[];
};

/** Accepts "https://github.com/owner/repo", "github.com/owner/repo", or bare "owner/repo". */
export function parseRepoUrl(input: string): { owner: string; repo: string } {
  const trimmed = input
    .trim()
    .replace(/\.git$/, "")
    .replace(/\/+$/, "");
  const withoutHost = trimmed.replace(/^https?:\/\//, "").replace(/^github\.com\//, "");
  const match = /^([^/\s]+)\/([^/\s]+)$/.exec(withoutHost);
  if (!match) {
    throw new Error(`"${input}" doesn't look like a GitHub repo — use "owner/repo" or a github.com URL.`);
  }
  return { owner: match[1], repo: match[2] };
}

function githubFetch(path: string, accept = "application/vnd.github+json"): Promise<Response> {
  const headers: Record<string, string> = { Accept: accept };
  const token = process.env.GITHUB_TOKEN;
  if (token) headers.Authorization = `Bearer ${token}`;
  return fetch(`https://api.github.com${path}`, { headers });
}

/** Fetches a raw file's contents; returns null on 404 (file/README doesn't exist)
 * or any other non-2xx response — callers treat a missing file as "skip it",
 * not a hard failure. */
async function fetchRawOrNull(path: string): Promise<string | null> {
  const res = await githubFetch(path, "application/vnd.github.raw");
  if (!res.ok) return null;
  return res.text();
}

/** Curated snapshot of a repo (metadata + README + package.json + top-level
 * file names) — the input to a one-off AI summarization, not a live context
 * source. Never called per task-parse, only from the manual "Sync" action. */
export async function getRepoSnapshot(repoUrl: string): Promise<RepoSnapshot> {
  const { owner, repo } = parseRepoUrl(repoUrl);
  const base = `/repos/${owner}/${repo}`;

  const metaRes = await githubFetch(base);
  if (metaRes.status === 404) {
    throw new Error(
      `GitHub repo "${owner}/${repo}" not found or private — add GITHUB_TOKEN in .env.local for private repos.`,
    );
  }
  if (metaRes.status === 403) {
    throw new Error("GitHub rate limit hit — try again later, or add GITHUB_TOKEN in .env.local to raise the limit.");
  }
  if (!metaRes.ok) {
    throw new Error(`GitHub API error (${metaRes.status}) fetching ${owner}/${repo}.`);
  }
  const meta = await metaRes.json();

  const [readme, packageJson] = await Promise.all([
    fetchRawOrNull(`${base}/readme`),
    fetchRawOrNull(`${base}/contents/package.json`),
  ]);

  let tree: string[] = [];
  const treeRes = await githubFetch(`${base}/contents`);
  if (treeRes.ok) {
    const entries = await treeRes.json();
    if (Array.isArray(entries)) {
      tree = entries
        .slice(0, TREE_ENTRY_LIMIT)
        .map((entry: { name: string; type: string }) => (entry.type === "dir" ? `${entry.name}/` : entry.name));
    }
  }

  return {
    fullName: typeof meta.full_name === "string" ? meta.full_name : `${owner}/${repo}`,
    description: meta.description ?? null,
    language: meta.language ?? null,
    topics: Array.isArray(meta.topics) ? meta.topics : [],
    readme: readme ? readme.slice(0, README_CHAR_LIMIT) : null,
    packageJson: packageJson ? packageJson.slice(0, PACKAGE_JSON_CHAR_LIMIT) : null,
    tree,
  };
}
