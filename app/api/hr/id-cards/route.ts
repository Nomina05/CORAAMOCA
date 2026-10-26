import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

async function sessionToken(){return (await cookies()).get(sessionCookie)?.value}
export async function GET(){const token=await sessionToken();if(!token)return NextResponse.json({error:"No autorizado."},{status:401});const {data,error}=await authDatabase().rpc("list_hr_id_cards",{p_token:token});if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message},{status:403});return NextResponse.json(data)}
export async function POST(request:Request){const token=await sessionToken();if(!token)return NextResponse.json({error:"No autorizado."},{status:401});const {data,error}=await authDatabase().rpc("save_hr_id_card",{p_token:token,p_data:await request.json()});if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message},{status:400});return NextResponse.json(data)}
export async function PATCH(request:Request){const token=await sessionToken();if(!token)return NextResponse.json({error:"No autorizado."},{status:401});const {data,error}=await authDatabase().rpc("save_hr_id_card_configuration",{p_token:token,p_data:await request.json()});if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message},{status:400});return NextResponse.json(data)}
