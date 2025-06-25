#!/usr/bin/perl
package parseMTGAlog;
use JSON;
use Digest::SHA qw(sha256_hex);
use DBI;
use Try::Tiny;
use Text::ANSITable;
use Date::Parse;
use Date::Format;
use Data::Dumper;

my $json = JSON->new->allow_nonref->utf8;

our $verbose = 0;
our $debug = 1;

our $userId;
our $userName = 'Xanatar';
our $sessionId;
our $matches;


our $dbh = DBI->connect("dbi:Pg:dbname=postgres;host=127.0.0.1", 'postgres', undef,{
      RaiseError => 1, PrintError => 0, AutoCommit => 1,
    }) or die "cannot connect: $DBI::errstr";

#  make dB tables
#
try {
    $dbh->do('create table mtga_deck_summary(_id int generated always as identity primary key, cid uuid not null, ev_name varchar(80), id uuid not null, sha256_hex varchar(255), name varchar(255), last_updated timestamp with time zone, last_played timestamp with time zone, format varchar(80) not null, win int, loss int, player varchar(16) not null, unique(player,cid,id));');
} catch {
};
try {
    $dbh->do('create table mtga_deck(_id int generated always as identity primary key, id uuid not null, cardId int not null, quantity int not null, player varchar(16) not null, unique(player, id,cardId));');
} catch {
};

try {
    $dbh->do('create or replace view vw_mtga_deck_stats as (with totals as ( select player, sum(win+loss) as total, sum(win) as total_wins, sum(loss) as total_losses, ev_name, name from mtga_deck_summary group by player, name,ev_name) select sq.player, sq.ev_name, total as played, total_wins, total_losses, ((total_wins/total::float))::decimal(5,2) as twin_ratio, sq.name, sum(win) as wins, sum(loss) as losses, ((sum(win)/sum(win+loss)::float))::decimal(5,2) as win_ratio, max(last_updated) as modified from (select player, sha256_hex, last_updated, name, ev_name, win, loss from mtga_deck_summary order by name) sq join totals on sq.player = totals.player and sq.name = totals.name and sq.ev_name = totals.ev_name group by sq.player, sq.name, sq.ev_name, total, total_wins, total_losses, sha256_hex order by player,name);');
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

        my $sth = $dbh->prepare("insert into mtga_deck_summary (player,sha256_hex,cid,name,id,last_played,last_updated,format, win, loss, ev_name) values (?,?,?,?,?,?,?,?,?,?,?) on conflict (player, cid, id) do nothing");
        try {
            $sth->execute($userName, $sha256, $c->{CourseId}, map { $summary->{$_} } qw/Name DeckId LastPlayed LastUpdated Format win loss ev_name/);
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
        $sth = $dbh->prepare("insert into mtga_deck (player,id,cardid,quantity) values (?,?,?,?)");
        foreach my $card (sort { $a->{cardId} <=> $b->{cardId} } @$maindeck) {
            try {
                $sth->execute($userName,$id,$card->{cardId}, $card->{quantity});
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

sub parseLog
{
    my $in_fh = shift || die 'usage parseLog($fh)';
    while (my $line = <$in_fh>) {
        chomp $line;
        chop($line) if ($line =~ m/\r$/);
        if ($line =~ /\[\w+\](\d{1,2}\/\d{1,2}\/\d{4} \d{1,2}:\d{2}:\d{2} [AP]M): (.*?): (\w+)$/) {
            my ($timestamp_str, $post,$op) = ($1,$2,$3);
            if ($post =~ /^((Match to )?)(.*?)(( to Match)?)$/) {
              $userId = $3;
            }

            my $timestamp = str2time($timestamp_str);
            my $formatted_timestamp = time2str("%Y-%m-%d %H:%M:%S", $timestamp);

            $line = <$in_fh>;
            chomp $line;
            chop($line) if ($line =~ m/\r$/);
            my $data;
            try {
              $data = decode_json($line);
            } catch {
              if ($line =~ /^\{$/) {
                $data = $line;
                do {
                  $line = <$in_fh>;
                  chomp $line;
                  chop($line) if ($line =~ m/\r$/);
                  $data .= $line;
                } until ($line =~ /^\}$/);
                try {
                  $data = decode_json($data);
                } catch {
                  print "uncaught JSON error: $_\ndata: $data\n";
                };
              } else {
                if ($line =~ /Message summarized because one or more GameStateMessages/) {
                } else {
                  print "op data [$line] not json\n";
                }
              }
            };


            my $ops = {
              authenticateResponse => sub {
                $sessionId = $data->{lcfirst($op)}->{sessionId};
                $userName = $data->{lcfirst($op)}->{screenName};
              },
              clientToGremessage => sub {
                my $type = $data->{payload}->{type};
                $type =~ s/.*?_//;
                my $subop = lcfirst($type);
                my $payload = $data->{payload}->{$subop};
                print "message type $subop\n" if ($verbose);
                print Dumper(\$payload) if ($verbose);
              },
              matchGameRoomStateChangedEvent => sub {
                my $payload = $data->{lcfirst($op)}->{gameRoomInfo};
                print Dumper(\$payload);

                my $state = $payload->{stateType};
                $state =~ s/.*?_//;
                my $matchId = $payload->{gameRoomConfig}->{matchId};

                print "**game state $state matchId: $matchId\n";

                if ($state eq "Playing") {
                  foreach my $player (@{ $payload->{gameRoomConfig}->{reservedPlayers} }) {
                    foreach (qw/userId playerName systemSeatId teamId platformId/) {
                      $matches->{$matchId}->{players}->{$player->{teamId}}->{$_} = $player->{$_};
                    }
                    printf "playerName: %s platformId: %s\n", $player->{playerName}, $player->{platformId};
                  }
                } elsif ($state eq "MatchCompleted") {
                  foreach (@{ $payload->{finalMatchResult}->{resultList} }) {
                    my $player = $matches->{$matchId}->{players}->{$_->{winningTeamId}};

                    $_->{reason} =~ s/.*?_//;
                    $_->{result} =~ s/.*?_//;
                    $_->{scope} =~ s/.*?_//;

                    printf "winners: %s (%s) reason: %s result: %s scope: %s\n",
                      $player->{playerName}, $player->{platformId}, $_->{reason}, $_->{result}, $_->{scope};
                  }
                }
              },
              greToClientEvent => sub {
                my @messages = @{$data->{lcfirst($op)}->{greToClientMessages}};
                foreach (@messages) {
                  my $type = $_->{type};
                  $type =~ s/.*?_//;
                  my $subop = lcfirst($type);
                  print "message type $subop\n" if ($verbose);
                  if (exists $_->{$subop}) {
                    my $payload = $_->{$subop};
                    print Dumper(\$payload) if ($verbose);
                  }
                  if (exists $_->{prompt}) {
                    print Dumper(\$_->{prompt}) if ($verbose);
                  }
                }
              },
              clientToGreuimessage => sub {
              },
            };
            print "$formatted_timestamp op: $op username: $userName userId: $userId sessionId: $sessionId\n";# if ($verbose);
            if (exists $ops->{lcfirst($op)}) {
              if (defined $ops->{lcfirst($op)} and defined $data) {
                $ops->{lcfirst($op)}->();
              }
            } else {
              print "unknown operand $op!\n";
            }

        }
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
            chop($line) if ($line =~ m/\r$/);
            my $r = $line;
            print "response op $op id $id res:" if ($verbose);
            if ($r =~ /\{.*\}/) {
                if ($debug) {
                  my $f = "/tmp/$op.$id.json";
                  open OUT, ">$f:encoding(UTF-8)";
                  #print OUT JSON->new->utf8->pretty->encode($r);
                  print OUT $json->pretty->encode( decode_json($r) );
                  close OUT;
                  print "wrote $f\n";
                }
                if ($op eq "EventGetCoursesV2" and defined $userName) {
                  processData($r)
                }
            } else {
                print "$r\n" if ($verbose);
            }
            print "\n" if ($verbose);
        }
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

  my @f = qw/player ev_name played total_wins total_losses twin_ratio name wins losses win_ratio modified/;

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
  $| = 1;
  print $t->draw;
}

package main;
use strict;
use warnings;
use 5.10.4;
use Time::HiRes qw(usleep nanosleep ualarm alarm);
use File::ChangeNotify;
use JSON;
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END); # better than using 0, 1, 2
use Try::Tiny;

binmode(STDOUT, ":encoding(UTF-8)");
#use open qw/ :std :encoding(utf8) /;

$SIG{ALRM} = sub {
  parseMTGAlog::printStats;
};

sub parseLog
{
    my $logfile = shift || die 'no logfile in parseLog';
    my $seek_pos = shift || 0;
    open my $in_fh, '<:raw', $logfile or die qq{Unable to open "$logfile" for input: $!};
    seek $in_fh, $seek_pos, SEEK_SET;

    parseMTGAlog::parseLog($in_fh);

    close $in_fh or die $!;
}

#my $steam = $ENV{HOME}.'/.local/share/Steam';
my $steam = '/space/steam2';
my $dir = shift @ARGV || $steam.'/steamapps/compatdata/2141910/pfx/drive_c/users/steamuser/AppData/LocalLow/Wizards Of The Coast/MTGA/';
my $logfile = "$dir/Player.log";

my $watcher = File::ChangeNotify->instantiate_watcher(
    directories => [ $dir ],  # Replace '.' with the directory containing your file
    filter      => qr/Player\.log$/, # Replace 'my_file.txt' with your filename
);

my $size = -s $logfile;
print "filesize $size\n" if ($verbose);
parseLog($logfile);
parseMTGAlog::printStats;
#while (my @events = $watcher->wait_for_events ) {
my $done;
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

