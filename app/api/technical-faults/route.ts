import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../auth/_supabase";
import {recordAudit} from "../auth/_audit";

export async function GET(){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const {data,error}=await authDatabase().rpc("list_technical_faults",{p_token:token});
 if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar las averías reportadas."},{status:400});
 return NextResponse.json(data);
}

export async function POST(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const body=await request.json();
 const ids=Array.isArray(body.faultIds)?body.faultIds:[];
 const {data,error}=await authDatabase().rpc("manage_technical_fault",{p_token:token,p_fault_ids:ids,p_status:body.status,p_comment:body.comment||""});
 if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible actualizar las averías."},{status:400});
 await recordAudit(request,token,{action:"ACTUALIZAR_AVERIA_TECNICA",module:"Dirección Técnica",entityType:"Avería",next:{ids,status:body.status,comment:body.comment}});
 return NextResponse.json(data);
}
