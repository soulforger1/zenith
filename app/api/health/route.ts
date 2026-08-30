import { NextResponse } from "next/server";

// Used by the Electron shell to detect that the standalone server is
// actually serving HTTP before opening the window. Deliberately has no DB
// import — this measures "is the server up", not "is the database
// reachable" (that's validated separately, during first-run setup).
export async function GET() {
  return NextResponse.json({ ok: true });
}
