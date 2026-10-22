import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const query=new URL(request.url).searchParams,year=Number(query.get("year")||new Date().getFullYear()),month=Number(query.get("month")||new Date().getMonth()+1);
  const {data,error}=await authDatabase().rpc("list_hr_payroll_budget",{p_token:token,p_year:year});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar el presupuesto de nómina."},{status:403});
  const {data:operations,error:operationsError}=await authDatabase().rpc("list_hr_payroll_budget_operations",{p_token:token,p_year:year,p_month:month});
  if(operationsError||!operations?.success)return NextResponse.json({error:operations?.error||operationsError?.message||"No fue posible calcular la ejecución presupuestaria."},{status:403});
  return NextResponse.json({year:data.year,lines:data.lines||[],caps:data.caps||[],summary:operations.summary||{},execution:operations.execution||[],monthly_execution:operations.monthly_execution||[],modifications:operations.modifications||[]});
}

export async function POST(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const body=await request.json();
  if(body.action==="modification"){
    const {data,error}=await authDatabase().rpc("save_hr_payroll_budget_modification",{p_token:token,p_line_id:body.line_id,p_type:body.type,p_amount:Number(body.amount),p_reason:body.reason,p_effective_month:Number(body.effective_month)});
    if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message},{status:400});return NextResponse.json(data);
  }
  if(body.action==="simulate"){
    const {data,error}=await authDatabase().rpc("simulate_hr_payroll_budget",{p_token:token,p_year:Number(body.year),p_month:Number(body.month),p_salary_increase:Number(body.salary_increase||0),p_new_hires:Number(body.new_hires||0),p_new_hire_salary:Number(body.new_hire_salary||0)});
    if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message},{status:400});return NextResponse.json(data);
  }
  if(body.action==="cap"){
    const {data,error}=await authDatabase().rpc("save_hr_payroll_budget_cap",{p_token:token,p_year:Number(body.year),p_fund:String(body.fund||""),p_amount:Number(body.amount)});
    if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible guardar el tope mensual."},{status:400});
    return NextResponse.json({success:true});
  }
  const {data,error}=await authDatabase().rpc("save_hr_payroll_budget_line",{p_token:token,p_id:body.id||null,p_data:body});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible guardar la partida de nómina."},{status:400});
  return NextResponse.json({success:true,id:data.id});
}
