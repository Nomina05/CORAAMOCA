"use client";

import {useEffect,useMemo,useRef,useState} from "react";
import type {LatLngExpression,Map as LeafletMap} from "leaflet";

type CustomerPoint={id:string;account_code:string;full_name:string;customer_category:string;sector:string;latitude:number|null;longitude:number|null};
type MeterPoint={id:string;meter_number:string;customer_name:string;status:string;last_reading:number|null;latitude:number|null;longitude:number|null};
type FaultPoint={id:string;fault_code:string;fault_type:string;description:string;zone:string;priority:string;status:string;affected_customers:number;reported_at:string;latitude:number|null;longitude:number|null};

export default function CommercialGeoMap({customers,meters}:{customers:CustomerPoint[];meters:MeterPoint[]}){
 const container=useRef<HTMLDivElement>(null);
 const mapRef=useRef<LeafletMap|null>(null);
 const [showCustomers,setShowCustomers]=useState(true);
 const [showMeters,setShowMeters]=useState(true);
 const [showFaults,setShowFaults]=useState(true);
 const [showResolvedFaults,setShowResolvedFaults]=useState(false);
 const [faults,setFaults]=useState<FaultPoint[]>([]);
 const customerPoints=useMemo(()=>customers.filter(item=>Number.isFinite(Number(item.latitude))&&Number.isFinite(Number(item.longitude))),[customers]);
 const meterPoints=useMemo(()=>meters.filter(item=>Number.isFinite(Number(item.latitude))&&Number.isFinite(Number(item.longitude))),[meters]);
 const faultPoints=useMemo(()=>faults.filter(item=>Number.isFinite(Number(item.latitude))&&Number.isFinite(Number(item.longitude))&&(showResolvedFaults||item.status!=="RESUELTA")),[faults,showResolvedFaults]);

 useEffect(()=>{let active=true;void fetch("/api/commercial/advanced",{cache:"no-store"}).then(response=>response.json()).then(body=>{if(active&&Array.isArray(body.faults))setFaults(body.faults)}).catch(()=>undefined);return()=>{active=false}},[]);

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
    map.fitBounds(bounds,{animate:false});
    map.setMinZoom(map.getBoundsZoom(bounds));
   }).catch(()=>{if(isCurrent()){map.fitBounds(provinceBounds);map.setMinZoom(map.getBoundsZoom(provinceBounds))}});
   window.setTimeout(()=>{if(isCurrent())map.invalidateSize({animate:false})},0);
  }).catch(()=>undefined);
  return()=>{
   active=false;
   const map=mapRef.current;
   mapRef.current=null;
   if(map){try{map.off();map.remove()}catch{/* La instancia ya fue desmontada por React. */}}
  };
 },[customerPoints,meterPoints,faultPoints,showCustomers,showMeters,showFaults]);

 return <section className="commercial-map-card"><header><div><span>MAPA GEOREFERENCIAL · PROVINCIA ESPAILLAT</span><h3>Usuarios, medidores y averías reportadas</h3><p>Los indicadores se incorporan automáticamente al registrar coordenadas válidas.</p></div><div className="commercial-map-filters"><label><input type="checkbox" checked={showCustomers} onChange={event=>setShowCustomers(event.target.checked)}/> Usuarios <i className="customer-dot"/></label><label><input type="checkbox" checked={showMeters} onChange={event=>setShowMeters(event.target.checked)}/> Medidores <i className="meter-dot"/></label><label><input type="checkbox" checked={showFaults} onChange={event=>setShowFaults(event.target.checked)}/> Averías <i className="fault-dot"/></label><label><input type="checkbox" checked={showResolvedFaults} onChange={event=>setShowResolvedFaults(event.target.checked)}/> Incluir resueltas</label></div></header><div className="fault-map-legend"><span><i className="fault-low"/> Media</span><span><i className="fault-high"/> Alta</span><span><i className="fault-critical"/> Crítica</span></div><div ref={container} className="commercial-map"/><footer><span><strong>{customerPoints.length}</strong> usuarios georreferenciados</span><span><strong>{meterPoints.length}</strong> medidores georreferenciados</span><span><strong>{faultPoints.length}</strong> averías visibles</span><span><strong>{faults.filter(item=>item.status!=="RESUELTA").length}</strong> averías abiertas</span><span><strong>{customers.length-customerPoints.length+meters.length-meterPoints.length+faults.filter(item=>!Number.isFinite(Number(item.latitude))||!Number.isFinite(Number(item.longitude))).length}</strong> registros pendientes de coordenadas</span></footer></section>;
}

function escapeHtml(value:string){return String(value??"").replace(/[&<>'"]/g,character=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"})[character]||character)}
