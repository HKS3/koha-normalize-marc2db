select value, group_concat(biblionumber), count(*) c from nm2db_v_record where tag = '440' and code = 'a' group by value order by c
desc limit 10;
