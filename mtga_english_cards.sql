select GrpId,
       ExpansionCode, 
       CollectorNumber, 
       max(le.Loc) as Title, 
( select string_agg(Loc,',') as CardType from Localizations_enUS les join Enums e on e.LocId = les.LocId join json_each('["' || replace(c.Types,',','","') || '"]') v on e.Value = v.value where e.Type = 'CardType') as CardType,
( select string_agg(Loc,',') as SubType from Localizations_enUS les join Enums e on e.LocId = les.LocId join json_each('["' || replace(c.Subtypes,',','","') || '"]') v on e.Value = v.value where e.Type = 'SubType') as SubType,
( select string_agg(Loc,',') as SuperType from Localizations_enUS les join Enums e on e.LocId = les.LocId join json_each('["' || replace(c.Supertypes,',','","') || '"]') v on e.Value = v.value where e.Type = 'SuperType') as SuperType,
(  select string_agg(Loc,',') as Colors from Localizations_enUS les join Enums e on e.LocId = les.LocId join json_each('["' || replace(c.Colors,',','","') || '"]') v on e.Value = v.value where e.Type = 'Color' ) as Colors,
       OldSchoolManaText,
       Power, 
       Toughness
from Cards c 
join Localizations l on c.TitleId = l.LocId
join Localizations_enUS le on l.LocId = le.LocId
where Order_Title not null 
group by GrpId;
