import assert from "node:assert/strict";
function normalize(v){const c=v.trim().replace(/[\s\-()]/g,"");if(/^09\d{8}$/.test(c))return `+963${c.slice(1)}`;if(/^\+9639\d{8}$/.test(c))return c;if(/^009639\d{8}$/.test(c))return `+${c.slice(2)}`;return null}
assert.equal(normalize("0944123456"),"+963944123456");
assert.equal(normalize("+963944123456"),"+963944123456");
assert.equal(normalize("00963944123456"),"+963944123456");
assert.equal(normalize("12345"),null);
function dist(a,b){const R=6371,r=x=>x*Math.PI/180,dLat=r(b.lat-a.lat),dLon=r(b.lng-a.lng),h=Math.sin(dLat/2)**2+Math.cos(r(a.lat))*Math.cos(r(b.lat))*Math.sin(dLon/2)**2;return 2*R*Math.asin(Math.sqrt(h))}
assert.ok(dist({lat:33.5,lng:36.3},{lat:33.51,lng:36.31})>0);
console.log("core tests passed");
