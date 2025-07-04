#!/bin/sh

SQL=mtga_english_cards.sql
STEAMDIR='/space/steam2'
DBDIR="$STEAMDIR/steamapps/common/MTGA/MTGA_Data/Downloads/Raw"
FILE=`find $DBDIR -iname 'Raw_CardDatabase*mtga'`

echo "found steam mtga cards db: $FILE"
if [ -e "$SQL" ]; then
  echo "making csv file"
#  cat $SQL | sqlite3 $FILE > /tmp/cards.psv
else
  echo "missing sql file $SQL!!!"
  exit
fi

echo "
drop view vw_mtga_deck;
drop table mtga_cards;
create table mtga_cards(GrpId int primary key,ExpansionCode text,CollectorNumber int,Title text,CardType text, Subtype text, Supertype text, Colors text, OldSchoolManaText text,Power text,Toughness text);
create view vw_mtga_deck as (
  with recent as (
    select * from (SELECT name, sha256_hex, ROW_NUMBER() OVER (
    PARTITION BY name
    ORDER BY last_updated DESC
) as row from mtga_deck_attributes) sq where row = 1
      ) 
   select player,a.name,c.title,c.expansioncode as code,c.collectornumber as num, quantity, 
     cardtype,oldschoolmanatext as cost,power as pow, toughness as tou, d.sha256_hex 
     from mtga_deck d 
     join mtga_cards c on d.cardid = c.grpid 
     join mtga_deck_attributes a on a.id = d.id and a.sha256_hex = d.sha256_hex
     join recent r on r.name = a.name and r.sha256_hex = a.sha256_hex 
);
" | psql -h localhost -U postgres

echo "\copy mtga_cards from '/tmp/cards.psv' with csv DELIMITER '|';" | psql -h localhost -U postgres
