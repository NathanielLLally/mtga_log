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
create view vw_mtga_deck as (select player,name,c.title,c.expansioncode as code,c.collectornumber as num, quantity, cardtype,oldschoolmanatext as cost,power as pow, toughness as tou from mtga_deck d join mtga_cards c on d.cardid = c.grpid join mtga_deck_attributes a on a.id = d.id);
" | psql -h localhost -U postgres

echo "\copy mtga_cards from '/tmp/cards.psv' with csv DELIMITER '|';" | psql -h localhost -U postgres
