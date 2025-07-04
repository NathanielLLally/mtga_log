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

my $sth = $dbh->prepare('select distinct name, format, player from mtga_deck_attributes where name not like ? group by player,format,name order by player,format,name;');
$sth->execute('?=?Loc/Decks/Precon%');
my $rs = $sth->fetchall_arrayref({});

foreach my $p (@$rs) {

    $sth = $dbh->prepare("select quantity||' '||title||' ('||code||') '||num from vw_mtga_deck where player = ? and name = ?");
    $sth->execute($p->{player},$p->{name});
    my $r = $sth->fetchall_arrayref();

    mkdir 'decklist';
    my $f = sprintf("%s.%s.mtga",$p->{player},$p->{name});
    $f =~ s/[^A-Za-z_0-9\.\-]/_/g;
    open FH, ">decklist/$f" || die " cannot opem $f for output $!";
    printf FH "About\nName %s\nDeck\n", $p->{name};

    foreach my $row (@$r) {
        printf FH "%s\n", $row->[0];
    }
    close FH;

    print "wrote decklist to $f\n";
    #open(X, "|-", "xclip") || die "cannot run xclip";
    #foreach my $row (@$rs) {
    #  printf X "%s\n", $row->[0];
    #}
    #close(X);
}
