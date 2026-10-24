import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";
export async function GET(request:Request){const token=(await cookies()).get(sessionCookie)?.value;if(!token)return NextResponse.json({error:"No autorizado."},{status:401});const query=new URL(request.url).searchParams,year=Number(query.get("year")),month=Number(query.get("month"));const {data,error}=await authDatabase().rpc("list_hr_official_reports",{p_token:token,p_year:year,p_month:month});if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible generar los reportes oficiales."},{status:403});return NextResponse.json(data)}
