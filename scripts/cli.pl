#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use JSON::Path;
use URI::Escape;
use HTML::Entities;
use Text::Table;

binmode STDOUT, ":encoding(UTF-8)";

dispatch();

# --- Command Mapping ---
sub dispatch {
    my @actions = qw(play pause stop next previous volume mute unmute);
    my @global = qw(music search all zones);
    my @per_zone = qw(queue zone);

    global_info("zones") if !scalar @ARGV;
    global_info(@ARGV) if (grep { $_ eq $ARGV[0] } @global);

    my ($zone, $command, @args) = @ARGV;
    usage() unless $zone && $command;

    zone_info($zone, $command, @args) if (grep { $_ eq $command } @per_zone);
    zone_command($zone, $command, @args) if (grep { $_ eq $command } @actions);
}

sub global_info {
    my ( $what, @args ) = @_;
    my %params = ("what" => $what);

    if ($what eq 'search') {
        usage("Missing search term") unless defined $args[0];
        $params{msearch} = $args[0];
    }

    if ($what eq 'music') {
        $params{mpath} = $args[0] ? $args[0] : "";
    }

    my $json = do_request(%params);

    show_info($what, $json);
}

sub zone_info {
    my ( $zone, $what, @args ) = @_;
    my %params = ("zone" => $zone, "what" => $what);
    my $json = do_request(%params);
}

sub zone_command {
    my ( $zone, $command, @args ) = @_;
    my %params = ("zone" => $zone, "action" => $command);

    if ($command eq 'volume') {
        usage("Missing volume level") unless defined $args[0];
        $params{volume} = $args[0];
    }

    my $json = do_request(%params);
}

sub do_request {
    my $base_url = "http://127.0.0.1:9999/api";
    my $ua = LWP::UserAgent->new;

    my %params = @_;

    # --- Build query URL ---
    my $query = join '&', map { uri_escape($_) . '=' . uri_escape($params{$_}) } keys %params;
    my $url = "$base_url?$query";

    # --- Make the request ---
    my $res = $ua->get($url);
    die "Request failed: " . $res->status_line unless $res->is_success;

    my $json = decode_json($res->decoded_content);
    return $json;
}

# --- Output formatting ---
sub show_info {
    my ( $command, $json ) = @_;

    my %field_map = (
        "queue" => [ qw(class name artist album streamContent) ],
        "music" => [ '$..name' ],
        "zones" => [ qw(zone/name active_state active_name)],
    );

    print $command, ":\n", to_json($json, { pretty => 1 });

    my @fields = $field_map{$command};
    if (@fields) {
        print_table($command, $json, \@fields)
    } elsif ($command eq 'zone') {
        printf "Zone: %s | Volume: %d | Muted: %s | State: %s\n",
            $json->{zone}->{name},
            $json->{render}->{volume},
            $json->{render}->{muted} ? "yes" : "no",
            $json->{av}->{transport_state}
    }
    else {
        print to_json($json, { pretty => 1 });
    }
}

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
