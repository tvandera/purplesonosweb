#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use URI::Escape;
use Getopt::Long;
use Text::Table;

# --- Command-line options ---
my %opt;
GetOptions(
    "zone=s"      => \$opt{zone},
    "mpath=s"     => \$opt{mpath},
    "queue=s"     => \$opt{queue},
    "what=s"      => \$opt{what},
    "action=s"    => \$opt{action},
    "lastupdate=i"=> \$opt{lastupdate},
    "link=s"      => \$opt{link},
    "volume=i"    => \$opt{volume},
    "savename=s"  => \$opt{savename},
    "NoWait=i"    => \$opt{NoWait},
    "help"        => sub { usage() },
) or usage();

sub usage {
    print <<"EOF";
Usage: $0 [--zone=Kitchen] [--what=queue] [--action=Play] ...

Options:
  --zone        Zone name (e.g. Kitchen)
  --mpath       Music path (e.g. /)
  --queue       Queue ID
  --what        Data to view: globals, music, zones, zone, queue, none, all
  --action      Action to perform (e.g. Play, Pause, SetVolume)
  --lastupdate  Last update timestamp
  --link        Zone to link with
  --volume      Set volume
  --savename    Save current queue
  --NoWait      Set to 1 to skip wait
  --help        Show this help
EOF
    exit;
}

# --- API Query Construction ---
my $base_url = "http://127.0.0.1:9999/api";
my @params;

foreach my $key (qw(zone mpath queue what action lastupdate link volume savename NoWait)) {
    push @params, uri_escape($key) . "=" . uri_escape($opt{$key}) if defined $opt{$key};
}

my $url = "$base_url?" . join("&", @params);

# --- HTTP GET Request ---
my $ua = LWP::UserAgent->new;
my $res = $ua->get($url);

unless ($res->is_success) {
    die "Request failed: " . $res->status_line;
}

my $json = decode_json($res->decoded_content);

# --- Tabular Display Function ---
sub display_table {
    my ($title, $list) = @_;
    return unless ref($list) eq 'ARRAY' && @$list;

    print "\n=== $title ===\n";
    my @columns = sort keys %{ $list->[0] };
    my $tb = Text::Table->new(@columns);

    for my $row (@$list) {
        $tb->add(map { defined $row->{$_} ? $row->{$_} : '' } @columns);
    }

    print $tb;
}

# --- Print Tables ---
display_table("Music Library", $json->{music_loop}) if $json->{music_loop};
display_table("Queue", $json->{queue_loop}) if $json->{queue_loop};
display_table("Zones", [ map { $_->{ZONE_MEMBERS}[0] } @{$json->{zones_loop}} ]) if $json->{zones_loop};

# --- Print remaining keys as JSON ---
my %skip = map { $_ => 1 } qw(music_loop queue_loop zones_loop);
my %other = map { $_ => $json->{$_} } grep { !$skip{$_} } keys %$json;

if (%other) {
    print "\n=== Other Data ===\n";
    print to_json(\%other, { pretty => 1 });
}
