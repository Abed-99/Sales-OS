export type VisitStatus = "new" | "contacted" | "interested";

export type VisitShop = {
  id: string;
  name: string;
  area: string | null;
  address: string | null;
  phone: string | null;
  whatsapp: string | null;
  latitude: number | string | null;
  longitude: number | string | null;
  status: VisitStatus;
  notes: string | null;
};

export type LocatedShop = VisitShop & { lat: number; lng: number };

export const STATUS_LABELS: Record<VisitStatus, string> = {
  new: "لسا ما انزار",
  contacted: "زرتو",
  interested: "مهتم",
};

export const STATUS_COLORS: Record<VisitStatus, string> = {
  new: "#70aee7",
  contacted: "#98aaa4",
  interested: "#d6ad55",
};

export const STATUS_CHIPS: Record<VisitStatus, string> = {
  new: "blue",
  contacted: "gray",
  interested: "orange",
};
