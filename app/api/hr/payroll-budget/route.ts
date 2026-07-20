import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const year=Number(new URL(request.url).searchParams.get("year")||new Date().getFullYear());
  const {data,error}=await authDatabase().rpc("list_hr_payroll_budget",{p_token:token,p_year:year});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar el presupuesto de nómina."},{status:403});
  return NextResponse.json({year:data.year,lines:data.lines||[],caps:data.caps||[]});
}

export async function POST(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const body=await request.json();
  if(body.action==="cap"){
    const {data,error}=await authDatabase().rpc("save_hr_payroll_budget_cap",{p_token:token,p_year:Number(body.year),p_fund:String(body.fund||""),p_amount:Number(body.amount)});
    if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible guardar el tope mensual."},{status:400});
    return NextResponse.json({success:true});
  }
  const {data,error}=await authDatabase().rpc("save_hr_payroll_budget_line",{p_token:token,p_id:body.id||null,p_data:body});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible guardar la partida de nómina."},{status:400});
  return NextResponse.json({success:true,id:data.id});
}
