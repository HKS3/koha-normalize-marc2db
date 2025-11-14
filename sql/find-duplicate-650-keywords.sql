select subj, 
	biblionumber,
	count(*) c 
from (select group_concat(code,"-",value) as subj, biblionumber from nm2db_v_record r 
where 
	tag = 650 
	and code in ('a', 'x', 'y', 'z', '2', 'v') 
	and value is not null 
	group by biblionumber, field_seq) as t 
	group by biblionumber,subj having c > 1;
