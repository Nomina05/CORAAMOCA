import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";
import {recordAudit} from "../../auth/_audit";

export async function GET(){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const {data,error}=await authDatabase().rpc("admin_user_governance_snapshot",{p_token:token});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible consultar el gobierno de usuarios."},{status:403});
  return NextResponse.json(data);
}

export async function POST(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const body=await request.json();
  const action=String(body.action||"");
  const payload=body.payload&&typeof body.payload==="object"?body.payload:{};
  const {data,error}=await authDatabase().rpc("admin_manage_user_governance",{p_token:token,p_action:action,p_payload:payload});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible completar la operación."},{status:400});
  await recordAudit(request,token,{action,module:"Usuarios",entityType:"Gobierno de acceso",entityId:payload.userId||payload.sessionId||payload.accessId||null,next:{...payload,permissions:payload.permissions?"[MATRIZ PROTEGIDA]":undefined},reason:payload.reason||payload.justification||""});
  return NextResponse.json({success:true});
}
