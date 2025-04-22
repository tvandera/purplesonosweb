#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use URI::Escape;
use HTML::Entities;
use Text::Table;

binmode STDOUT, ":encoding(UTF-8)";

my ($zone, $command, @args) = @ARGV;

my $base_url = "http://127.0.0.1:9999/api";
my $ua = LWP::UserAgent->new;
my %params;

if (!$zone && !$command) {
    $command = "zones";
} elsif ($zone && $command) {
    $params{zone} = $zone;
} else {
    usage();
}

# --- Command Mapping ---
my @actions = qw(play pause stop next previous volume mute unmute search);
my @info = qw(queue info music all zones);

if (grep { $_ eq $command } @actions) {
    $params{action} = $command;
    $params{nowait} = "1";
} elsif (grep { $_ eq $command } @info) {
    $params{what} = $command;
} else {
    usage("Unknown command: $command");
}

if ($command eq 'volume') {
    usage("Missing volume level") unless defined $args[0];
    $params{volume} = $args[0];
}

if ($command eq 'search') {
    usage("Missing search term") unless defined $args[0];
    $params{msearch} = $args[0];
}

if ($command eq 'music') {
    $params{mpath} = $args[0] ? $args[0] : "";
}

# --- Build query URL ---
my $query = join '&', map { uri_escape($_) . '=' . uri_escape($params{$_}) } keys %params;
my $url = "$base_url?$query";

# --- Make the request ---
my $res = $ua->get($url);
die "Request failed: " . $res->status_line unless $res->is_success;

my $json = decode_json($res->decoded_content);

# --- Output formatting ---
if ($command eq 'queue' && $json->{queue}) {
    my @fields = qw(class name artist album streamContent);
    print_table("Queue", $json->{queue}, \@fields);
}
elsif ($command eq 'music' && $json->{children}) {
    my @fields = qw(id name);
    print_table("Music", $json->{children}, \@fields);
}
elsif ($command eq 'zones' && $json->{loop}) {
    my @fields = qw(zone_name active_state active_name);
    print_table("Zones", $json->{zones_loop}, \@fields);
}
elsif ($command eq 'info') {
    printf "Zone: %s | Volume: %d | Muted: %s | Status: %s | Track: %s\n",
        $json->{name},
        $json->{volume},
        $json->{muted} ? "yes" : "no",
        ($json->{PLAYING} ? "playing" : $json->{active_STOPPED} ? "stopped" : "paused"),
        $json->{name} || "-";
}
elsif ($command =~ /^(play|pause|stop|next|previous|volume|mute|unmute)$/) {
    print "Action '$command' sent to zone '$zone'.\n";
}
else {
    print to_json($json, { pretty => 1 });
}

# --- Helpers ---

sub print_table {
    my ($title, $data, $cols) = @_;
    return unless @$data;

    #all cols if none specificied
    $cols = [ sort keys %{ $data->[0] } ] unless $cols;

    my $separator =  \' | ';
    my @headers = map { $separator, $_ } @$cols, $separator;

    my $tb = Text::Table->new(@headers);
    for my $row (@$data) {
        print "row = ", %$row, "\n";
        my @values = map { decode_entities( $row->{$_} ) // '' } @$cols;
        print("values = ", @values, "\n");
        $tb->add(@values);
    }
    print "\n=== $title ===\n";
    print $tb;
}

sub usage {
    my ($msg) = @_;
    print "\n$msg\n" if $msg;
    print <<'EOF';

Usage:
  music
  music <zone> <command> [args]

Commands:
  play            Start playback
  pause           Pause playback
  stop            Stop playback
  next            Next track
  previous        Previous track
  volume <level>  Set volume (0-100)
  mute            Mute zone
  unmute          Unmute zone
  queue           Show current queue
  info            Show zone info
  music           Browse top-level music items
  all             Dump all available data for the zone

Examples:
  music Kitchen play
  music Kitchen volume 25
  music "Living Room" info

EOF
    exit 1;
}
