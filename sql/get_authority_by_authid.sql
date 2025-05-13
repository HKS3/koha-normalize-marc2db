select 
	r.authid, 
	f.sequence field_order, 
	s.sequence subfield_order, 
	tag, 
	indicator1, 
	indicator2, 
	code, 
	value 
from 
	nm2db_fields f join nm2db_subfields s on 
	f.id = s.field_id
    join nm2db_records r on 
	r.id = f.record_id     
where 
	r.authid = 11 order by tag;
