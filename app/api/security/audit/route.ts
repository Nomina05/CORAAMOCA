import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase,sessionCookie } from "../../auth/_supabase";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const url=new URL(request.url);
  const {data,error}=await authDatabase().rpc("list_complete_audit",{
    p_token:token,p_limit:Math.min(Number(url.searchParams.get("limit")||200),1000),p_module:url.searchParams.get("module")||null,
  });
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible consultar la auditoría."},{status:403});
  return NextResponse.json({items:data.items||[]});
}
