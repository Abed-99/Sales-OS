begin;

grant select on public.inventory_stock to authenticated;
grant select on public.warehouses to authenticated;

commit;
