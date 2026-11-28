// Rota de callback do Supabase Auth: troca `code` por sessão (PKCE) e
// redireciona para o destino informado. Cookies de sessão são gravados aqui.
import { NextResponse, type NextRequest } from "next/server";

import { createSupabaseServerClient } from "@/modules/auth";

export async function GET(request: NextRequest): Promise<NextResponse> {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const nextParam = searchParams.get("next") ?? "/portal";
  // `next` só aceita caminho interno (evita open redirect).
  const next = nextParam.startsWith("/") && !nextParam.startsWith("//") ? nextParam : "/portal";

  if (code) {
    const supabase = await createSupabaseServerClient();
    await supabase.auth.exchangeCodeForSession(code);
  }

  return NextResponse.redirect(new URL(next, origin));
}
