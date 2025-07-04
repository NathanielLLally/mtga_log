#!/usr/bin/perl
use warnings;
use strict;
use 5.10.4;
use DBI;
use Try::Tiny;
use Text::ANSITable;

binmode(STDOUT, ":encoding(UTF-8)");


our $dbh = DBI->connect("dbi:Pg:dbname=postgres;host=127.0.0.1", 'postgres', undef,{
      RaiseError => 1, PrintError => 0, AutoCommit => 1,
    }) or die "cannot connect: $DBI::errstr";

my ($player, $deck, $sha256);

my $sth = $dbh->prepare('select distinct player from mtga_deck_attributes');
$sth->execute();
my $rs = $sth->fetchall_arrayref({});

PLAYER:
say 'choose player';

my $i = 1;
foreach my $p (@$rs) {
  printf "%s: %s\n", $i++, $p->{player};
}

$player = <STDIN>;
chomp $player;

if (not exists $rs->[$player - 1]) {
  say "[$player] invalid input";
  goto PLAYER;
}
$player = $rs->[$player - 1]->{player};

DECK:
say "decks for $player";
$sth = $dbh->prepare('select distinct name, format from mtga_deck_attributes where player = ? and name not like ? group by format,name order by format,name;');
$sth->execute($player,'?=?Loc/Decks/Precon%');
$rs = $sth->fetchall_arrayref({});

my $i = 1;
foreach my $p (@$rs) {
  printf "%s: %s\t\t%s\n", $i++, $p->{name}, $p->{format};
}

$deck = <STDIN>;
chomp $deck;

if (not exists $rs->[$deck - 1]) {
  say "[$deck] invalid input";
  goto DECK;
}
$deck = $rs->[$deck - 1]->{name};

$sth = $dbh->prepare("select quantity||' '||title||' ('||code||') '||num from vw_mtga_deck where player = ? and name = ?");
$sth->execute($player,$deck);
$rs = $sth->fetchall_arrayref();

open FH, ">deck.mtga" || die " cannot opem deck.mtga for output $!";
printf FH "About\nName %s\nDeck\n", $deck;

my $str;
foreach my $row (@$rs) {
  printf FH "%s\n", $row->[0];
  $str .= $row->[0]."\n";
}
close FH;
print "wrote decklist to deck.mtga\n";
system("xclip -selection clipboard -i", $str);
#open(X, "|-", "xclip") || die "cannot run xclip";
#foreach my $row (@$rs) {
#  printf X "%s\n", $row->[0];
#}
#close(X);
`xclip deck.mtga`
