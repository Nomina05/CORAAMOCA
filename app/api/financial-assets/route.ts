import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../auth/_supabase";
import {recordAudit} from "../auth/_audit";

export async function GET(){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const {data,error}=await authDatabase().rpc("list_financial_assets",{p_token:token});
 if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar los activos."},{status:400});
 return NextResponse.json({assets:data.assets||[]});
}

export async function POST(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const body=await request.json();
 const {data,error}=await authDatabase().rpc("create_financial_asset",{p_token:token,p_data:body});
 if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible registrar el activo."},{status:400});
 await recordAudit(request,token,{action:"ACTIVO_REGISTRADO",module:"Finanzas",entityType:"Activo",entityId:data.id,projectId:body.project_id,next:body,reason:body.description||""});
 return NextResponse.json(data);
}

export async function PATCH(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const body=await request.json();
 const {data,error}=await authDatabase().rpc("transition_financial_asset",{p_token:token,p_asset_id:body.id,p_action:body.action||"ADVANCE",p_comments:body.comments||""});
 if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cambiar el estado del activo."},{status:400});
 await recordAudit(request,token,{action:body.action==="RETURN"?"ACTIVO_DEVUELTO":"ACTIVO_AVANZADO",module:"Finanzas",entityType:"Activo",entityId:body.id,projectId:data.project_id,previous:{status:data.previous_status},next:{status:data.status},reason:body.comments||""});
 return NextResponse.json(data);
}
