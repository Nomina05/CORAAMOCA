import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const url=new URL(request.url),now=new Date();
 const year=Number(url.searchParams.get("year")||now.getFullYear()),month=Number(url.searchParams.get("month")||now.getMonth()+1);
 if(!Number.isInteger(year)||month<1||month>12)return NextResponse.json({error:"Período inválido."},{status:400});
 const {data,error}=await authDatabase().rpc("list_hr_vacancies",{p_token:token,p_year:year,p_month:month});
 if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible consultar las vacantes."},{status:403});
 return NextResponse.json({items:data.items||[],areas:data.areas||[],period_end:data.period_end});
}
