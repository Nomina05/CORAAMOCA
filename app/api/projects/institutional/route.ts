import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";
import {recordAudit} from "../../auth/_audit";

export async function GET(){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const {data,error}=await authDatabase().rpc("list_institutional_projects",{p_token:token});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar los proyectos institucionales."},{status:403});
  return NextResponse.json({projects:data.projects||[]});
}

export async function POST(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const body=await request.json();
  const {id,...project}=body;
  const {data,error}=await authDatabase().rpc("save_institutional_project",{p_token:token,p_project_id:id||null,p_data:project});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible guardar el proyecto institucional."},{status:400});
  await recordAudit(request,token,{action:id?"PROYECTO_INSTITUCIONAL_MODIFICADO":"PROYECTO_INSTITUCIONAL_CREADO",module:"Proyectos institucionales",entityType:"Proyecto",entityId:data.id,previous:data.previous,next:project,reason:project.description||""});
  return NextResponse.json({success:true,id:data.id});
}
