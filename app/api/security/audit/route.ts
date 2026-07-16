import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase, sessionCookie } from "../../auth/_supabase";

export async function GET(request: Request) {
  const token = (await cookies()).get(sessionCookie)?.value;
  if (!token) return NextResponse.json({ error: "No autorizado." }, { status: 401 });
  const limit = Math.min(Number(new URL(request.url).searchParams.get("limit") || 100), 500);
  const { data, error } = await authDatabase().rpc("admin_list_security_audit", { p_token: token, p_limit: limit });
  if (error || !data?.success) return NextResponse.json({ error: data?.error || "No fue posible consultar la auditoría." }, { status: 403 });
  return NextResponse.json({ items: data.items || [] });
}
