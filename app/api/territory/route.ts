import {NextResponse} from "next/server";
import {cookies} from "next/headers";
import {authDatabase,sessionCookie} from "../auth/_supabase";
export async function GET(){const token=(await cookies()).get(sessionCookie)?.value;if(!token)return NextResponse.json({error:"No autorizado."},{status:401});const {data,error}=await authDatabase().rpc("list_espaillat_territory",{p_token:token});if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar el catálogo territorial."},{status:400});return NextResponse.json({municipalities:data.municipalities||[],districts:data.districts||[],sectors:data.sectors||[]});}
