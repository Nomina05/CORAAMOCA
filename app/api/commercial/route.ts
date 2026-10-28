import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../auth/_supabase";
import {recordAudit} from "../auth/_audit";

export async function GET(){const token=(await cookies()).get(sessionCookie)?.value;if(!token)return NextResponse.json({error:"No autorizado."},{status:401});const {data,error}=await authDatabase().rpc("list_commercial_dashboard",{p_token:token});if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar Gestión Comercial."},{status:400});return NextResponse.json(data);}
export async function POST(request:Request){const token=(await cookies()).get(sessionCookie)?.value;if(!token)return NextResponse.json({error:"No autorizado."},{status:401});const body=await request.json();const {data,error}=await authDatabase().rpc("manage_commercial_record",{p_token:token,p_action:body.action,p_data:body.data||{}});if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible registrar la operación comercial."},{status:400});await recordAudit(request,token,{action:`COMERCIAL_${body.action}`,module:"Gestión Comercial",entityType:body.action,entityId:data.id,next:body.data,reason:"Registro desde módulo comercial"});return NextResponse.json(data);}
