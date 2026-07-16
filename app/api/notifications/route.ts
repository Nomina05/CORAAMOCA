import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { authDatabase,sessionCookie } from "../auth/_supabase";

export async function GET(){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const {data,error}=await authDatabase().rpc("list_app_notifications",{p_token:token});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar las notificaciones."},{status:400});
  return NextResponse.json({items:data.items||[]});
}

export async function PATCH(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const body=await request.json().catch(()=>({}));
  const {data,error}=await authDatabase().rpc("mark_app_notifications_read",{p_token:token,p_notification_id:body.id||null});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible actualizar las notificaciones."},{status:400});
  return NextResponse.json({success:true});
}
