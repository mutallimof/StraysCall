-- ============================================================================
-- Stray's Call — migration 042: app name in two notification texts
-- ----------------------------------------------------------------------------
-- Two notification bodies written by the database still said "PawLine":
--   admin_set_vet_status (003)  "...appears to rescuers on PawLine."
--   vet_identity_guard (007)    "...until the PawLine team re-verifies it."
-- Neither function is redefined by a later migration (040 only adds a
-- BEFORE INSERT filter on notifications), so both are copied from 003 and
-- 007 verbatim, with only that text changed.
--
-- Already stored notifications with the old texts are updated by exact
-- match on body. UPDATE fires no trigger on notifications and the push
-- webhook runs on INSERT only, so nothing is re-sent.
--
-- CREATE OR REPLACE keeps the existing owner, grants and the
-- on_vet_identity_change trigger. Run after 001-041. Idempotent.
-- ============================================================================

create or replace function public.admin_set_vet_status(p_vet uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only.'; end if;
  if p_status not in ('approved', 'rejected', 'pending') then
    raise exception 'Invalid status.';
  end if;

  update public.vets set status = p_status where id = p_vet;

  insert into public.notifications (profile_id, type, title, body)
  values (p_vet, 'case_update',
          case p_status when 'approved' then 'Your clinic is verified'
                        when 'rejected' then 'Clinic verification declined'
                        else 'Clinic under review' end,
          case p_status when 'approved' then 'Your clinic now appears to rescuers on Stray''s Call.'
                        else 'Please contact support if you believe this is a mistake.' end);
end;
$$;

create or replace function public.vet_identity_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'approved'
     and (new.clinic_name is distinct from old.clinic_name
          or new.address is distinct from old.address) then
    new.status := 'pending';

    insert into public.notifications (profile_id, type, title, body)
    values (new.id, 'case_update', 'Clinic details changed — re-verification needed',
            'Because your clinic name or address changed, your listing is hidden until the Stray''s Call team re-verifies it.');

    insert into public.notifications (profile_id, type, title, body)
    select p.id, 'case_update', 'Vet re-verification needed',
           coalesce(old.clinic_name, 'A clinic') || ' changed its name/address and needs re-approval.'
    from public.profiles p where p.is_admin = true;
  end if;
  return new;
end;
$$;

update public.notifications
   set body = 'Your clinic now appears to rescuers on Stray''s Call.'
 where body = 'Your clinic now appears to rescuers on PawLine.';

update public.notifications
   set body = 'Because your clinic name or address changed, your listing is hidden until the Stray''s Call team re-verifies it.'
 where body = 'Because your clinic name or address changed, your listing is hidden until the PawLine team re-verifies it.';
