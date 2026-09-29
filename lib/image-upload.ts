import type { SupabaseClient } from "@supabase/supabase-js";

/** تصغير صورة الموبايل (بتكون كبيرة) لـ 900px JPEG قبل الرفع. */
export async function shrinkImage(file: File, maxSide = 900, quality = 0.82): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  const context = canvas.getContext("2d");
  if (!context) throw new Error("canvas");
  context.fillStyle = "#ffffff";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  return await new Promise<Blob>((resolve, reject) =>
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error("blob"))),
      "image/jpeg",
      quality,
    ),
  );
}

/** بيرفع صورة الصنف لمجلد الشركة وبيرجّع رابطها العام. */
export async function uploadProductImage(
  supabase: SupabaseClient,
  companyId: string,
  file: File,
): Promise<string> {
  const blob = await shrinkImage(file);
  const path = `${companyId}/${crypto.randomUUID()}.jpg`;
  const { error } = await supabase.storage
    .from("product-images")
    .upload(path, blob, { contentType: "image/jpeg", upsert: false });
  if (error) throw error;
  return supabase.storage.from("product-images").getPublicUrl(path).data.publicUrl;
}
