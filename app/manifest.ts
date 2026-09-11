import type { MetadataRoute } from "next";
export default function manifest(): MetadataRoute.Manifest { return { name:"Sales OS", short_name:"Sales OS", start_url:"/", display:"standalone", background_color:"#07110e", theme_color:"#19b889", lang:"ar", dir:"rtl" }; }
