#!/bin/sh

SQL=mtga_english_cards.sql
STEAMDIR='/space/steam2'
DBDIR="$STEAMDIR/steamapps/common/MTGA/MTGA_Data/Downloads/Raw"
FILE=`find $DBDIR -iname 'Raw_CardDatabase*mtga'`

echo "found steam mtga cards db: $FILE"
if [ -e "$SQL" ]; then
  echo "making csv file"
  cat $SQL | sqlite3 $FILE > /tmp/cards.psv
else
  echo "missing sql file $SQL!!!"
  exit
fi

echo "
drop view vw_mtga_deck;
drop table mtga_cards;
create table mtga_cards(GrpId int primary key,ExpansionCode text,CollectorNumber int,Title text,CardType text, Subtype text, Supertype text, Colors text, ColorIdentity text, OldSchoolManaText text,Power text,Toughness text);
create view vw_mtga_deck as (
  WITH recent AS (
         SELECT sq.name,
            sq.sha256_hex,
            sq.row
           FROM ( SELECT mtga_deck_attributes.name,
                    mtga_deck_attributes.sha256_hex,
                    row_number() OVER (PARTITION BY mtga_deck_attributes.name ORDER BY mtga_deck_attributes.last_updated DESC) AS row
                   FROM mtga_deck_attributes) sq
          WHERE sq.row = 1
        )
 SELECT a.player,
    a.name,
    c.title,
    c.expansioncode AS code,
    c.collectornumber AS num,
    d.quantity,
    c.cardtype,
    c.subtype,
    c.supertype,
    c.colors,
    c.coloridentity,
    c.oldschoolmanatext AS cost,
    c.power AS pow,
    c.toughness AS tou
   FROM mtga_deck d
     JOIN mtga_cards c ON d.cardid = c.grpid
     JOIN mtga_deck_attributes a ON a.id = d.id AND a.sha256_hex::text = d.sha256_hex::text
     JOIN recent r ON r.name::text = a.name::text AND r.sha256_hex::text = a.sha256_hex::text
);
" | psql -h localhost -U postgres

echo "\copy mtga_cards from '/tmp/cards.psv' with csv DELIMITER '|';" | psql -h localhost -U postgres
