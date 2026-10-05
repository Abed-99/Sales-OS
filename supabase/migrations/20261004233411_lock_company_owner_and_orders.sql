SET local check_function_bodies = off;

DROP POLICY "sales_orders_create" ON "public"."sales_orders";

DROP POLICY "sales_orders_update" ON "public"."sales_orders";

CREATE OR REPLACE FUNCTION public.protect_company_identity()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
begin
  -- المالك الأساسي ورقم الشركة ما بيتغيّروا من التطبيق أبدًا
  -- (وإلا أي مدير معه "إدارة الشركة" بيقدر يحط حالو مالك ويشيل المالك الحقيقي).
  if new.id is distinct from old.id then
    raise exception 'Company id cannot be changed';
  end if;

  if new.owner_user_id is distinct from old.owner_user_id
     and auth.uid() is not null
  then
    raise exception 'Company owner cannot be changed';
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."protect_company_identity"() FROM PUBLIC, "anon";

CREATE TRIGGER protect_company_identity_trigger
  BEFORE UPDATE OF id, owner_user_id ON public.companies
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_company_identity();

GRANT EXECUTE ON FUNCTION "public"."protect_company_identity"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."protect_company_identity"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."protect_company_identity"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."protect_company_identity"() TO "service_role";
