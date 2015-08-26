select 
  route_id, 
  min(least(FROM_COUNTY_CUMMILE_BEGIN_MP, TO_COUNTY_CUMMILE_BEGIN_MP)) as min,
  max(greatest(TO_COUNTY_CUMMILE_BEGIN_MP, FROM_COUNTY_CUMMILE_BEGIN_MP)) as max
from PMS_DW_DIM_COPY group by route_id;

select * from (
select 
  route_id,
  min(PMS_MIN) as PMS_MIN,
  max(PMS_MAX) as PMS_MAX,
  min(BEG_POINT) as HPMS_MIN,
  max(END_POINT) as HPMS_MAX
from 
  (select 
    p.route_id as route_id, p.PMS_MIN, p.PMS_MAX, s.BEG_POINT, s.END_POINT
  from 
    (select 
      route_id, 
      min(least(FROM_COUNTY_CUMMILE_BEGIN_MP, TO_COUNTY_CUMMILE_BEGIN_MP)) as PMS_MIN,
      max(greatest(TO_COUNTY_CUMMILE_BEGIN_MP, FROM_COUNTY_CUMMILE_BEGIN_MP)) as PMS_MAX
    from PMS_DW_DIM_COPY
    where COLLECTION_YEAR = 2012 
    group by route_id) p
  join alfo_segmented s on p.route_id = s.route_id)
group by route_id ) where pms_max > hpms_max or pms_min < hpms_min;

select count(distinct route_id) from PMS_DW_DIM_COPY where COLLECTION_YEAR = 2012;
select count(distinct route_id) from PMS_DW_DIM_COPY where COLLECTION_YEAR = 2012 and route_id in (select route_id from hpms_section);
select count(*) from PMS_DW_DIM_COPY  where COLLECTION_YEAR = 2012;

select min(collection_year), max(collection_year) from PMS_DW_DIM_COPY;
select count(distinct route_id) from PMS_DW_DIM_COPY where COLLECTION_YEAR = 2012;