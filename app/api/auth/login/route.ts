import { NextResponse } from "next/server";
import { authDatabase, cookieOptions, sessionCookie } from "../_supabase";
import { recordAudit } from "../_audit";

export async function POST(request: Request) {
  const { username, password } = await request.json();
  const { data, error } = await authDatabase().rpc("login_app_user", { p_username: username, p_password: password });
  if (error || !data?.token) {
    const status = data?.code === "SUSPENDED" ? 403 : data?.code === "LOCKED" ? 423 : 401;
    return NextResponse.json({ error: data?.error || "Usuario o contraseña incorrectos.", code: data?.code }, { status });
  }
  const response = NextResponse.json({ user: data.user });
  const userAgent=request.headers.get("user-agent")||"";
  const ip=request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()||request.headers.get("x-real-ip")||"";
  const device=/mobile|android|iphone|ipad/i.test(userAgent)?"Dispositivo móvil":"Equipo de escritorio";
  await authDatabase().rpc("register_session_context",{p_token:data.token,p_ip:ip,p_user_agent:userAgent,p_device:device});
  await recordAudit(request,data.token,{action:"INICIO_SESION",module:"Seguridad",entityType:"Sesión",entityId:data.user?.id,next:{username:data.user?.username}});
  response.cookies.set(sessionCookie, data.token, cookieOptions);
  return response;
}
