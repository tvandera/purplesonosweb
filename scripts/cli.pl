#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use JSON::Path;
use URI::Escape;
use HTML::Entities;
use Text::Table;
use Encode qw(decode encode);

binmode STDOUT, ":encoding(UTF-8)";

dispatch();

# --- Command Mapping ---
sub dispatch {
    my @actions = qw(play pause stop next previous volume mute unmute);
    my @global = qw(music search all zones);
    my @per_zone = qw(queue zone);

    return global_info("zones") if !scalar @ARGV;
    return global_info(@ARGV) if (grep { $_ eq $ARGV[0] } @global);

    my ($zone, $command, @args) = @ARGV;
    usage() unless $zone && $command;

    return zone_info($zone, $command, @args) if (grep { $_ eq $command } @per_zone);
    return zone_command($zone, $command, @args) if (grep { $_ eq $command } @actions);

    return usage();
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
    show_info($what, $json);
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

    # my $raw = $res->decoded_content(charset => 'none');  # gets raw bytes, no decoding
    # binmode(STDOUT, ":encoding(UTF-8)");
    # use Data::Dumper;
    # print Dumper(substr($raw, 0, 100));
    # my $decoded = decode('Windows-1252', $raw, Encode::FB_CROAK);
    # print Dumper(substr($decoded, 0, 100));

    my $decoded = $res->decoded_content();
    return decode_json($decoded);
}

# --- Output formatting ---
sub show_info {
    my ( $command, $json ) = @_;

    my %field_map = (
        "queue" => [ qw(pos id name creator album class) ],
        "music" => [ qw(id name) ],
        "zones" => [ '$.*.zone.name', '$.*.av.transport_state'],
    );

    my %sort_functions = (
        "queue" => sub { $a->[0] <=> $b->[0] },
        "music" => sub { $a->[0] cmp $b->[0] },
        "zones" => sub { $a->[0] cmp $b->[0] },
    );

    print $command, ":\n", to_json($json, { pretty => 1 });

    my $fields = $field_map{$command};
    my $sorter = $sort_functions{$command};
    if ($fields) {
        print_table($command, $json, $fields, $sorter);
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
    my ($title, $json, $cols, $sorter) = @_;
    my @paths = map { JSON::Path->new($_ =~ m/^\$/ ? $_  : '$.*.' . $_ ) } @$cols;
    my @values = map { [ $_->values($json) ] } @paths;
    my @transposed = map { my $i = $_; [ map $_->[$i], @values ] } 0..$#{$values[0]};
    @transposed = sort $sorter @transposed;
    my $separator =  \' | ';
    my @headers = map { (split /\./)[-1] } @$cols;
    @headers = map { $separator, $_ } @headers, $separator;

    my $tb = Text::Table->new(@headers)->load(@transposed);
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
