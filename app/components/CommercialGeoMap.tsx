"use client";

import {useCallback,useEffect,useMemo,useRef,useState} from "react";
import type {LatLngExpression,Map as LeafletMap} from "leaflet";

type CustomerPoint={id:string;account_code:string;full_name:string;customer_category:string;municipality:string;district:string;sector:string;latitude:number|null;longitude:number|null};
type MeterPoint={id:string;customer_id:string;meter_number:string;customer_name:string;status:string;last_reading:number|null;municipality:string;district:string;sector:string;latitude:number|null;longitude:number|null};
type FaultPoint={id:string;customer_id:string|null;fault_code:string;fault_type:string;description:string;zone:string;priority:string;status:string;affected_customers:number;reported_at:string;latitude:number|null;longitude:number|null};
type TerritoryItem={id:string;name:string;municipality:string;district:string};
type PlacePoint={id:string;name:string;category:string;address:string;latitude:number;longitude:number};
const normalized=(value:string|undefined|null)=>String(value||"").trim().normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase();
const unique=(values:string[])=>Array.from(new Set(values.map(value=>value.trim()).filter(Boolean))).sort((a,b)=>a.localeCompare(b,"es"));

export default function CommercialGeoMap({customers,meters,territory}:{customers:CustomerPoint[];meters:MeterPoint[];territory?:{municipalities:TerritoryItem[];districts:TerritoryItem[];sectors:TerritoryItem[]}}){
 const container=useRef<HTMLDivElement>(null);
 const mapRef=useRef<LeafletMap|null>(null);
 const [showCustomers,setShowCustomers]=useState(true);
 const [showMeters,setShowMeters]=useState(true);
 const [showFaults,setShowFaults]=useState(true);
 const [showPlaces]=useState(true);
 const [showResolvedFaults,setShowResolvedFaults]=useState(false);
 const [expanded,setExpanded]=useState(false);
 const [faults,setFaults]=useState<FaultPoint[]>([]);
 const [places,setPlaces]=useState<PlacePoint[]>([]);
 const [municipality,setMunicipality]=useState("");
 const [district,setDistrict]=useState("");
 const [sector,setSector]=useState("");
 const hasTerritorialFilter=Boolean(municipality||district||sector);
 const municipalities=useMemo(()=>unique([...(territory?.municipalities||[]).map(item=>item.name),...customers.map(item=>item.municipality)]),[customers,territory]);
 const districts=useMemo(()=>unique([...(territory?.districts||[]).filter(item=>!municipality||normalized(item.municipality)===normalized(municipality)).map(item=>item.name),...customers.filter(item=>!municipality||normalized(item.municipality)===normalized(municipality)).map(item=>item.district)]),[customers,territory,municipality]);
 const sectors=useMemo(()=>unique([...(territory?.sectors||[]).filter(item=>(!municipality||normalized(item.municipality)===normalized(municipality))&&(!district||normalized(item.district)===normalized(district))).map(item=>item.name),...customers.filter(item=>(!municipality||normalized(item.municipality)===normalized(municipality))&&(!district||normalized(item.district)===normalized(district))).map(item=>item.sector)]),[customers,territory,municipality,district]);
 const locationMatches=useCallback((item:{municipality?:string;district?:string;sector?:string})=>(!municipality||normalized(item.municipality)===normalized(municipality))&&(!district||normalized(item.district)===normalized(district))&&(!sector||normalized(item.sector)===normalized(sector)),[municipality,district,sector]);
 const filteredCustomers=useMemo(()=>customers.filter(locationMatches),[customers,locationMatches]);
 const filteredMeters=useMemo(()=>meters.filter(locationMatches),[meters,locationMatches]);
 const customerById=useMemo(()=>new Map(customers.map(item=>[item.id,item])),[customers]);
 const filteredFaults=useMemo(()=>faults.filter(item=>{const customer=item.customer_id?customerById.get(item.customer_id):undefined;return locationMatches({municipality:customer?.municipality,district:customer?.district,sector:customer?.sector||item.zone})}),[faults,customerById,locationMatches]);
 const customerPoints=useMemo(()=>filteredCustomers.filter(item=>Number.isFinite(Number(item.latitude))&&Number.isFinite(Number(item.longitude))),[filteredCustomers]);
 const meterPoints=useMemo(()=>filteredMeters.filter(item=>Number.isFinite(Number(item.latitude))&&Number.isFinite(Number(item.longitude))),[filteredMeters]);
 const faultPoints=useMemo(()=>filteredFaults.filter(item=>Number.isFinite(Number(item.latitude))&&Number.isFinite(Number(item.longitude))&&(showResolvedFaults||item.status!=="RESUELTA")),[filteredFaults,showResolvedFaults]);

 useEffect(()=>{let active=true;void fetch("/api/commercial/advanced",{cache:"no-store"}).then(response=>response.json()).then(body=>{if(active&&Array.isArray(body.faults))setFaults(body.faults)}).catch(()=>undefined);return()=>{active=false}},[]);
 useEffect(()=>{let active=true;void fetch("/api/map-places").then(response=>response.json()).then(body=>{if(active&&Array.isArray(body.places))setPlaces(body.places)}).catch(()=>undefined);return()=>{active=false}},[]);
 useEffect(()=>{if(!expanded)return;const close=(event:KeyboardEvent)=>{if(event.key==="Escape")setExpanded(false)};document.body.classList.add("commercial-map-expanded-open");window.addEventListener("keydown",close);return()=>{document.body.classList.remove("commercial-map-expanded-open");window.removeEventListener("keydown",close)}},[expanded]);

 useEffect(()=>{
  let active=true;
  void import("leaflet").then(L=>{
   if(!active||!container.current)return;
   const provinceBounds=L.latLngBounds([[19.3077463,-70.6106827],[19.7140174,-70.0818209]]);
   const map=L.map(container.current,{zoomControl:true,attributionControl:true,maxBounds:provinceBounds.pad(.015),maxBoundsViscosity:1});
   mapRef.current=map;
   const isCurrent=()=>active&&mapRef.current===map&&Boolean(container.current);
   map.createPane("provinceMask");
   const maskPane=map.getPane("provinceMask");if(maskPane){maskPane.style.zIndex="650";maskPane.style.pointerEvents="none"}
   L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",{maxZoom:19,attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'}).addTo(map);
   const coordinates:LatLngExpression[]=[];
   if(showCustomers)customerPoints.forEach(item=>{
    const position:LatLngExpression=[Number(item.latitude),Number(item.longitude)];coordinates.push(position);
    L.marker(position,{icon:L.divIcon({className:"commercial-map-marker",html:'<span class="customer-marker">U</span>',iconSize:[28,28],iconAnchor:[14,14]})}).addTo(map).bindPopup(`<strong>${escapeHtml(item.full_name)}</strong><br>No. contrato: ${escapeHtml(item.account_code)}<br>Categoría: ${escapeHtml(item.customer_category||"Sin categoría")}<br>Sector: ${escapeHtml(item.sector||"Sin sector")}`);
   });
   if(showMeters)meterPoints.forEach(item=>{
    const position:LatLngExpression=[Number(item.latitude),Number(item.longitude)];coordinates.push(position);
    L.marker(position,{icon:L.divIcon({className:"commercial-map-marker",html:'<span class="meter-marker">M</span>',iconSize:[26,26],iconAnchor:[13,13]})}).addTo(map).bindPopup(`<strong>Medidor ${escapeHtml(item.meter_number)}</strong><br>Usuario: ${escapeHtml(item.customer_name)}<br>Estado: ${escapeHtml(item.status)}<br>Última lectura: ${item.last_reading??"Sin lectura"}`);
   });
   if(showFaults)faultPoints.forEach(item=>{
    const position:LatLngExpression=[Number(item.latitude),Number(item.longitude)];coordinates.push(position);
    const priority=String(item.priority||"Media").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g,"");
    L.marker(position,{icon:L.divIcon({className:"commercial-map-marker fault-map-icon",html:`<span class="fault-marker ${priority}">!</span>`,iconSize:[32,32],iconAnchor:[16,16]})}).addTo(map).bindPopup(`<strong>${escapeHtml(item.fault_code)} · ${escapeHtml(item.fault_type)}</strong><br>${escapeHtml(item.description)}<br>Zona: ${escapeHtml(item.zone||"Sin zona")}<br>Prioridad: ${escapeHtml(item.priority)}<br>Estado: ${escapeHtml(item.status)}<br>Clientes afectados: ${Number(item.affected_customers||0)}<br>Reportada: ${new Date(item.reported_at).toLocaleString("es-DO")}`);
   });
   if(showPlaces)places.forEach(item=>{const position:LatLngExpression=[item.latitude,item.longitude];L.marker(position,{icon:L.divIcon({className:"commercial-map-marker",html:'<span class="place-marker">●</span>',iconSize:[18,18],iconAnchor:[9,9]})}).addTo(map).bindTooltip(escapeHtml(item.name),{direction:"top",offset:[0,-8]}).bindPopup(`<strong>${escapeHtml(item.name)}</strong><br>${escapeHtml(placeCategory(item.category))}${item.address?`<br>${escapeHtml(item.address)}`:""}`)});
   const focusSelection=(fallbackBounds:typeof provinceBounds)=>{if(hasTerritorialFilter&&coordinates.length===1){map.setView(coordinates[0],15,{animate:false});return}if(hasTerritorialFilter&&coordinates.length>1){map.fitBounds(L.latLngBounds(coordinates),{padding:[45,45],maxZoom:15,animate:false});return}map.fitBounds(fallbackBounds,{animate:false})};
   void fetch("/data/espaillat.geojson").then(response=>response.json()).then(boundary=>{
    if(!isCurrent())return;
    const province=L.geoJSON(boundary,{pane:"provinceMask",style:{color:"#0c6c8a",weight:3,fill:false,opacity:1}}).addTo(map);
    const geometry=boundary?.features?.[0]?.geometry;
    if(geometry?.type==="Polygon"){
     const provinceRing=geometry.coordinates[0].map((point:number[])=>[point[1],point[0]] as [number,number]);
     const world:[[number,number],[number,number],[number,number],[number,number]]=[[-90,-180],[-90,180],[90,180],[90,-180]];
     L.polygon([world,provinceRing],{pane:"provinceMask",stroke:false,fill:true,fillColor:"#dbe3e7",fillOpacity:.9,fillRule:"evenodd",interactive:false}).addTo(map);
    }
    province.bringToFront();
    const bounds=province.getBounds();
    map.setMaxBounds(bounds.pad(.015));
    focusSelection(bounds);
    map.setMinZoom(map.getBoundsZoom(bounds));
   }).catch(()=>{if(isCurrent()){focusSelection(provinceBounds);map.setMinZoom(map.getBoundsZoom(provinceBounds))}});
   window.setTimeout(()=>{if(isCurrent())map.invalidateSize({animate:false})},0);
  }).catch(()=>undefined);
  return()=>{
   active=false;
   const map=mapRef.current;
   mapRef.current=null;
   if(map){try{map.off();map.remove()}catch{/* La instancia ya fue desmontada por React. */}}
  };
 },[customerPoints,meterPoints,faultPoints,places,showCustomers,showMeters,showFaults,showPlaces,hasTerritorialFilter,expanded]);

 return <><section className={`commercial-map-card${expanded?" is-expanded":""}`} role={expanded?"dialog":undefined} aria-modal={expanded||undefined} aria-label={expanded?"Mapa georreferencial ampliado":undefined}><header><div><span>MAPA GEOREFERENCIAL · PROVINCIA ESPAILLAT</span><h3>Usuarios, medidores y averías reportadas</h3><p>Filtre territorialmente los registros visibles del mapa.</p></div><div className="commercial-map-header-actions"><div className="commercial-map-filters"><label><input type="checkbox" checked={showCustomers} onChange={event=>setShowCustomers(event.target.checked)}/> Usuarios <i className="customer-dot"/></label><label><input type="checkbox" checked={showMeters} onChange={event=>setShowMeters(event.target.checked)}/> Medidores <i className="meter-dot"/></label><label><input type="checkbox" checked={showFaults} onChange={event=>setShowFaults(event.target.checked)}/> Averías <i className="fault-dot"/></label><label><input type="checkbox" checked={showResolvedFaults} onChange={event=>setShowResolvedFaults(event.target.checked)}/> Incluir resueltas</label></div><button type="button" className="primary commercial-map-expand" onClick={()=>setExpanded(value=>!value)}>{expanded?"Cerrar mapa":"Ampliar mapa"}</button></div></header><div className="commercial-map-location-filters"><label>Municipio<select value={municipality} onChange={event=>{setMunicipality(event.target.value);setDistrict("");setSector("")}}><option value="">Todos los municipios</option>{municipalities.map(value=><option key={value}>{value}</option>)}</select></label><label>Distrito municipal<select value={district} disabled={!districts.length} onChange={event=>{setDistrict(event.target.value);setSector("")}}><option value="">Todos los distritos</option>{districts.map(value=><option key={value}>{value}</option>)}</select></label><label>Sector<select value={sector} disabled={!sectors.length} onChange={event=>setSector(event.target.value)}><option value="">Todos los sectores</option>{sectors.map(value=><option key={value}>{value}</option>)}</select></label>{(municipality||district||sector)&&<button type="button" className="outline" onClick={()=>{setMunicipality("");setDistrict("");setSector("")}}>Limpiar filtros</button>}</div><div className="fault-map-legend"><span><i className="fault-low"/> Media</span><span><i className="fault-high"/> Alta</span><span><i className="fault-critical"/> Crítica</span></div><div ref={container} className="commercial-map"/><footer><span><strong>{customerPoints.length}</strong> usuarios georreferenciados</span><span><strong>{meterPoints.length}</strong> medidores georreferenciados</span><span><strong>{faultPoints.length}</strong> averías visibles</span><span><strong>{filteredFaults.filter(item=>item.status!=="RESUELTA").length}</strong> averías abiertas</span><span><strong>{filteredCustomers.length-customerPoints.length+filteredMeters.length-meterPoints.length+filteredFaults.filter(item=>!Number.isFinite(Number(item.latitude))||!Number.isFinite(Number(item.longitude))).length}</strong> registros pendientes de coordenadas</span></footer></section>{expanded&&<button type="button" className="commercial-map-backdrop" aria-label="Cerrar mapa ampliado" onClick={()=>setExpanded(false)}/>}</>;
}

function escapeHtml(value:string){return String(value??"").replace(/[&<>'"]/g,character=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"})[character]||character)}
function placeCategory(value:string){return ({school:"Centro educativo",college:"Centro educativo",university:"Universidad",hospital:"Centro de salud",clinic:"Clínica",pharmacy:"Farmacia",bank:"Entidad financiera",townhall:"Institución pública",government:"Institución pública",supermarket:"Supermercado",mall:"Centro comercial"} as Record<string,string>)[value]||value.replaceAll("_"," ")}
