update nm2db_v_record set
  value = replace(value, 'Perl', 'PERL') 
  where tag = '245' and code = 'a' and value regexp 'perl';
