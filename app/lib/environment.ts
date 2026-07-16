const required=["NEXT_PUBLIC_SUPABASE_URL","NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"] as const;

export function validateEnvironment(){
  const missing=required.filter(key=>!process.env[key]?.trim());
  if(missing.length)throw new Error(`Configuración incompleta: faltan ${missing.join(", ")}.`);
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL!;
  if(!url.startsWith("https://")||!url.includes(".supabase.co"))throw new Error("NEXT_PUBLIC_SUPABASE_URL no contiene una dirección válida de Supabase.");
  return {
    supabaseUrl:url,
    publishableKey:process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    environment:process.env.NEXT_PUBLIC_APP_ENV||process.env.VERCEL_ENV||process.env.NODE_ENV||"development",
  };
}
