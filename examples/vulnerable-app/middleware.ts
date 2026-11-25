import { NextResponse, type NextRequest } from "next/server";

export function middleware(req: NextRequest) {
  if (!req.cookies.get("session")) {
    return NextResponse.redirect(new URL("/login", req.url));
  }
  return NextResponse.next();
}

// Only the admin pages are covered. /api/admin/* and every other API route are not.
export const config = { matcher: ["/admin/:path*"] };
