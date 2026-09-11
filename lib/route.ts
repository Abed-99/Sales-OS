export type GeoPoint={id:string;name:string;lat:number;lng:number};
function distance(a:{lat:number;lng:number},b:{lat:number;lng:number}){
  const R=6371,toRad=(x:number)=>x*Math.PI/180;
  const dLat=toRad(b.lat-a.lat), dLon=toRad(b.lng-a.lng);
  const h=Math.sin(dLat/2)**2+Math.cos(toRad(a.lat))*Math.cos(toRad(b.lat))*Math.sin(dLon/2)**2;
  return 2*R*Math.asin(Math.sqrt(h));
}
export function nearestNeighborRoute(points:GeoPoint[],start?:{lat:number;lng:number}){
  const left=[...points],ordered:GeoPoint[]=[]; let cur=start || (left[0]?{lat:left[0].lat,lng:left[0].lng}:{lat:0,lng:0});
  while(left.length){ let best=0,bestD=Infinity; left.forEach((p,i)=>{const d=distance(cur,p);if(d<bestD){bestD=d;best=i}}); const [pick]=left.splice(best,1); ordered.push(pick); cur={lat:pick.lat,lng:pick.lng}; }
  return ordered;
}
