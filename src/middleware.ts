// Middleware: refresh da sessão (barato) + proteção grossa de /portal/**.
// Validação completa (papel + empresa ativa) acontece nas páginas via módulo
// auth; aqui só redirecionamos sem sessão para /login?next=…
import { type NextRequest, NextResponse } from "next/server";

import { createSupabaseMiddlewareClient, type MiddlewareCookieJar } from "@/modules/auth/infrastructure/supabase-middleware-client";

export async function middleware(request: NextRequest) {
  const jar: MiddlewareCookieJar = { writes: [] };
  const supabase = createSupabaseMiddlewareClient(request, jar);
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname, search } = request.nextUrl;
  // Criado após getUser para repassar os cookies possivelmente renovados.
  let response = NextResponse.next({ request });

  if (pathname.startsWith("/portal") && !user) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = "/login";
    loginUrl.search = "";
    loginUrl.searchParams.set("next", `${pathname}${search}`);
    response = NextResponse.redirect(loginUrl);
  } else if (pathname === "/login" && user) {
    const portalUrl = request.nextUrl.clone();
    portalUrl.pathname = "/portal";
    portalUrl.search = "";
    response = NextResponse.redirect(portalUrl);
  }

  for (const { name, value, options } of jar.writes) {
    response.cookies.set({ name, value, ...(options ?? {}) });
  }
  return response;
}

export const config = {
  matcher: ["/login", "/portal/:path*"],
};
