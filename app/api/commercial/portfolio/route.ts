import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";
import {recordAudit} from "../../auth/_audit";

export async function GET(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const url=new URL(request.url),year=Number(url.searchParams.get("year")||new Date().getFullYear()),month=Number(url.searchParams.get("month")||new Date().getMonth()+1);
 const {data,error}=await authDatabase().rpc("list_commercial_portfolio_management",{p_token:token,p_year:year,p_month:month});
 if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar carteras y metas."},{status:400});
 return NextResponse.json(data);
}

export async function POST(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const body=await request.json();
 const {data,error}=await authDatabase().rpc("manage_commercial_portfolio",{p_token:token,p_action:body.action,p_data:body.data||{}});
 if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible procesar la operación."},{status:400});
 await recordAudit(request,token,{action:`CARTERA_COMERCIAL_${body.action}`,module:"Gestión Comercial",entityType:"Cartera, meta e incentivo",entityId:data.id,next:body.data});
 return NextResponse.json(data);
}
