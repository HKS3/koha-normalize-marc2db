-- Find $9-linked authority records whose authtypecode does not match
-- what MARC21 expects for the tag it's linked from (see bib_heading_fields
-- in koha/C4/Heading/MARC21.pm for the source mapping).
select
	b.biblionumber,
	b.tag,
	b.code,
	b.value as linked_authid,
	ah.authtypecode as actual_authtype,
	m.auth_type as expected_authtype
from nm2db_v_record b
join (
	select '100' as tag, 'PERSO_NAME' as auth_type union all
	select '110', 'CORPO_NAME' union all
	select '111', 'MEETI_NAME' union all
	select '130', 'UNIF_TITLE' union all
	select '147', 'NAME_EVENT' union all
	select '148', 'CHRON_TERM' union all
	select '150', 'TOPIC_TERM' union all
	select '151', 'GEOGR_NAME' union all
	select '155', 'GENRE/FORM' union all
	select '162', 'MED_PERFRM' union all
	select '180', 'TOPIC_TERM' union all
	select '181', 'GEOGR_NAME' union all
	select '182', 'CHRON_TERM' union all
	select '185', 'GENRE/FORM' union all
	select '440', 'UNIF_TITLE' union all
	select '600', 'PERSO_NAME' union all
	select '610', 'CORPO_NAME' union all
	select '611', 'MEETI_NAME' union all
	select '630', 'UNIF_TITLE' union all
	select '648', 'CHRON_TERM' union all
	select '650', 'TOPIC_TERM' union all
	select '651', 'GEOGR_NAME' union all
	select '655', 'GENRE/FORM' union all
	select '690', 'TOPIC_TERM' union all
	select '691', 'GEOGR_NAME' union all
	select '696', 'PERSO_NAME' union all
	select '697', 'CORPO_NAME' union all
	select '698', 'MEETI_NAME' union all
	select '699', 'UNIF_TITLE' union all
	select '700', 'PERSO_NAME' union all
	select '710', 'CORPO_NAME' union all
	select '711', 'MEETI_NAME' union all
	select '730', 'UNIF_TITLE' union all
	select '800', 'PERSO_NAME' union all
	select '810', 'CORPO_NAME' union all
	select '811', 'MEETI_NAME' union all
	select '830', 'UNIF_TITLE'
) m on m.tag = b.tag
join auth_header ah on ah.authid = cast(b.value as unsigned)
where b.record_type = 'biblio'
  and b.code = '9'
	and b.value regexp '^[0-9]+$'
	and ah.authtypecode <> m.auth_type
	and not (ah.authtypecode = 'TOPIC_TERM' and m.auth_type = 'GENRE/FORM')
order by b.biblionumber, b.tag;
