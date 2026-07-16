import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase,sessionCookie } from "../auth/_supabase";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const value=new URL(request.url).searchParams.get("year");
  const {data,error}=await authDatabase().rpc("get_institutional_reports",{p_token:token,p_year:value?Number(value):null});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible generar los reportes."},{status:403});
  return NextResponse.json(data);
}
