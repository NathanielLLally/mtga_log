#!/usr/bin/perl
package parseMTGAlog;
use JSON;
use Digest::SHA qw(sha256_hex);
use DBI;
use Try::Tiny;
use Text::ANSITable;

our $dbh = DBI->connect("dbi:Pg:dbname=postgres;host=127.0.0.1", 'postgres', undef,{
      RaiseError => 1, PrintError => 0, AutoCommit => 1,
    }) or die "cannot connect: $DBI::errstr";

#  make dB tables
#
try {
    $dbh->do('create table mtga_deck_summary(_id int generated always as identity primary key, cid uuid not null, ev_name varchar(80), id uuid not null, sha256_hex varchar(255), name varchar(255), last_updated timestamp with time zone, last_played timestamp with time zone, format varchar(80) not null, win int, loss int, unique(cid,id));');
} catch {
};
try {
    $dbh->do('create table mtga_deck(_id int generated always as identity primary key, id uuid not null, cardId int not null, quantity int not null, unique(id,cardId));');
} catch {
};

try {
    $dbh->do('create or replace view vw_mtga_deck_stats as (with totals as ( select sum(win+loss) as total, sum(win) as total_wins, sum(loss) as total_losses, ev_name, name from mtga_deck_summary group by name,ev_name) select sq.ev_name, total as played, total_wins, total_losses, ((total_wins/total::float))::decimal(5,2) as twin_ratio, sq.name, sum(win) as wins, sum(loss) as losses, ((sum(win)/sum(win+loss)::float))::decimal(5,2) as win_ratio, max(last_updated) as modified from (select sha256_hex, last_updated, name, ev_name, win, loss from mtga_deck_summary order by name) sq join totals on sq.name = totals.name and sq.ev_name = totals.ev_name group by sq.name, sq.ev_name, total, total_wins, total_losses, sha256_hex order by name);');
} catch {
};

sub insert_deck
{
    my $c = shift || die 'insert_deck($course_json_data)';

    my ($id,$maindeck) = ($c->{CourseDeckSummary}->{DeckId}, $c->{CourseDeck}->{MainDeck});

    #  generate sha256_hex of a pipe delimited string containing cardid:quantity sorted by cardid
    #  this will& digest be used to detect changes and track a seperate win/loss stat as compared to deck name & digest
    #
    my $psv = join("|",
        map { sprintf("%u:%u", $_->{cardId}, $_->{quantity}) }
        sort { $a->{cardId} <=> $b->{cardId} } @$maindeck
    );
    my $sha256 = sha256_hex($psv);
    # flatten deck summary data
    #
    my $summary = {};
    foreach (qw/DeckId Name/) {
        $summary->{$_} = $c->{CourseDeckSummary}->{$_};
    }
    foreach (@{ $c->{CourseDeckSummary}->{Attributes} }) {
        $summary->{$_->{name}} = $_->{value};
    }
    $summary->{loss} = ($c->{CurrentLosses} || 0);
    $summary->{win} = ($c->{CurrentWins} || 0);
    $summary->{ev_name} = $c->{InternalEventName};

=head2    # check for existing
    #
    my $sth = $dbh->prepare("select * from mtga_deck_summary where id = ? and sha256_hex = ?");
    $sth->execute($id, $sha256);
    my $rs = $sth->fetchall_arrayref({});
    my $rowcount = $#{$rs};

    #  either brand new deck data, or a change in deck contents
    #
    if ($rowcount == -1) {
=cut

        my $sth = $dbh->prepare("insert into mtga_deck_summary (sha256_hex,cid,name,id,last_played,last_updated,format, win, loss, ev_name) values (?,?,?,?,?,?,?,?,?,?) on conflict (cid, id) do nothing");
        try {
            $sth->execute($sha256, $c->{CourseId}, map { $summary->{$_} } qw/Name DeckId LastPlayed LastUpdated Format win loss ev_name/);
        } catch {
            #            if ($_ =~ /
            die "uncaught DBI error: $_\n";
        };
        $sth = $dbh->prepare("select * from mtga_deck where id = ?");
        $sth->execute($id);
        my $rs = $sth->fetchall_arrayref({});
        if ($#{$rs} > -1) {
            #
            #  this means it is first recorded alteration of deck,id
            #  
            try {
                $sth = $dbh->prepare("delete from mtga_deck where id = ?");
                $sth->execute($id);
            } catch {
                die "uncaught DBI error: $_\n";
            };
        }

        #  either way now insert deck data
        #
        $sth = $dbh->prepare("insert into mtga_deck (id,cardid,quantity) values (?,?,?)");
        foreach my $card (sort { $a->{cardId} <=> $b->{cardId} } @$maindeck) {
            try {
                $sth->execute($id,$card->{cardId}, $card->{quantity});
            } catch {
                print "uncaught DBI error: $_\n";
            };
        }
        #}
    return $sha256;
}

sub processData
{
    my $json = shift || die 'usage: processData $jsonData';
    my $data = decode_json($json);

    foreach my $c (@{$data->{Courses}}) {
        printf "Course %s (%s):\n",$c->{InternalEventName},$c->{CourseId};
        my $stat = 0;
        $stat = $stat - ($c->{CurrentLosses} || 0);
        $stat = $stat + ($c->{CurrentWins} || 0);
        printf "\t\"%s\" (%s)\n",$c->{CourseDeckSummary}->{Name},$c->{CourseDeckSummary}->{DeckId};

        my $sha256 = insert_deck($c);
        printf "\tdeck sha %s\n", $sha256;
    }
}

sub printStats
{
  my $sth = $dbh->prepare("select * from  vw_mtga_deck_stats");
  $sth->execute();
  my $rs = $sth->fetchall_arrayref({});

  my $t = Text::ANSITable->new;
  $t->border_style('UTF8::SingleLineBold');  # if not, a nice default is picked
  $t->color_theme('Data::Dump::Color::Light');  # if not, a nice default is picked
  $t->{header_bgcolor} = '000000';
  $t->{header_fgcolor} = 'ffffff';
  $t->{header_align} = 'middle';

  my @f = qw/ev_name played total_wins total_losses twin_ratio name wins losses win_ratio modified/;
  my @h = @f;
  $h[4] = 'twin_pct';
  $h[8] = 'win_pct';
  $t->columns([@h]);
  $t->set_column_style('twin_pct'   , formats => [[num=>{decimal_digits=>2, style=>'percent'}]]);
  $t->set_column_style('win_pct'   , formats => [[num=>{decimal_digits=>2, style=>'percent'}]]);
  foreach my $row (@$rs) {
      #      print join('|', map { $row->{$_} } @f). "\n";
      $t->add_row([map { $row->{$_} } @f]);
  }
  print $t->draw;
}

package main;
use strict;
use warnings;
use 5.10.4;
use Date::Parse;
use Date::Format;
use Time::HiRes qw(usleep nanosleep ualarm alarm);
use File::ChangeNotify;
use JSON;
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END); # better than using 0, 1, 2
use Data::Dumper;

binmode(STDOUT, ":encoding(UTF-8)");

my $verbose = 0;
my $debug = 0; #spits out files of pretty json reencoded operation response data
my $json = JSON->new->allow_nonref;

$SIG{ALRM} = sub {
  parseMTGAlog::printStats;
};

sub parseLog
{
    my $logfile = shift || die 'no logfile in parseLog';
    my $seek_pos = shift || 0;
    open my $in_fh, '<', $logfile or die qq{Unable to open "$logfile" for input: $!};
    seek $in_fh, $seek_pos, SEEK_SET;

    #do {
    while (my $line = <$in_fh>) {
        chomp $line;
        if ($line =~ /\[\w+\](\d{1,2}\/\d{1,2}\/\d{4} \d{1,2}:\d{2}:\d{2} [AP]M)/) {
            my ($timestamp_str) = ($1);

            my $timestamp = str2time($timestamp_str);
            my $formatted_timestamp = time2str("%Y-%m-%d %H:%M:%S", $timestamp);

            print "Timestamp: $formatted_timestamp\n" if ($verbose);
        }
        #if ($line =~ /\=\=\> (\w+) (\{.*\})$/) {
        if ($line =~ /\=\=\> (\w+) (\{.*\})/) {
            my ($op, $json) = ($1,$2);
            print "op: $op\n" if ($verbose);
            my $msg = decode_json($json);
            print Dumper(\$msg) if ($verbose);
        }
        if ($line =~ /\<\=\= (\w+)\((.*?)\)/) {
            my ($op, $id) = ($1,$2);
            $line = <$in_fh>;
            chomp $line;
            my $r = $line;
            print "response op $op id $id res:" if ($verbose);
            if ($r =~ /\{.*\}/) {
                if ($debug) {
                  $r = decode_json($r);
                  my $f = "/tmp/$op.$id.json";
                  open OUT, ">$f";
                  print OUT $json->pretty->encode($r);
                  close OUT;
                  print "wrote $f\n";
                }
                if ($op eq "EventGetCoursesV2") {
                  parseMTGAlog::processData($r)
                }
            } else {
                print "$r\n" if ($verbose);
            }
            print "\n" if ($verbose);
        }
    }
    #usleep 10000;
    #} until (defined $done);

    close $in_fh or die $!;
}

my $done;
my $watcher = File::ChangeNotify->instantiate_watcher(
    directories => [ $dir ],  # Replace '.' with the directory containing your file
    filter      => qr/Player\.log$/, # Replace 'my_file.txt' with your filename
);

#my $steam = $ENV{HOME}.'/.local/share/Steam';
my $steam = '/space/steam2';
my $dir = shift @ARGV || $steam.'/steamapps/compatdata/2141910/pfx/drive_c/users/steamuser/AppData/LocalLow/Wizards Of The Coast/MTGA/';
my $logfile = "$dir/Player.log";

my $size = -s $logfile;
print "filesize $size\n" if ($verbose);
parseLog($logfile);
parseMTGAlog::printStats;
#while (my @events = $watcher->wait_for_events ) {
do {
    foreach my $event ($watcher->new_events) {
        my $newsize = -s $event->path;
        if ($newsize > $size) {
            print "new event\t";
            #        my $event = pop @events;
            print "  File: " . $event->path . ", Type: " . $event->type;
            print " size ".-s $event->path;
            print "\n";
            parseLog($event->path, $size);
            alarm(5);
            $size = $newsize;
        }
    }
    usleep 1000;
} while (not defined $done);

