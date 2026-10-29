#!/usr/bin/perl

use strict;
use warnings;

use Net::Async::HTTP::Server;
use IO::Async::Loop;

use HTTP::Response;

my $loop = IO::Async::Loop->new();

my $httpserver = Net::Async::HTTP::Server->new(
   on_request => sub {
      my $self = shift;
      my ( $req ) = @_;

      my @lines = map { "$_ Hello, world!"; } (1..1000);
      my $content = join "\n", @lines;
      my $response = HTTP::Response->new( 200 );
      $response->add_content( $content );
      $response->content_type( "text/plain" );
      $response->content_length( length $response->content );
      $req->respond( $response );
   },
);

$loop->add( $httpserver );

$httpserver->listen(
   addr => {
      family   => "inet6",
      socktype => "stream",
      port     => 18080,
   },
   on_listen_error => sub { die "Cannot listen - $_[-1]\n" },
);

my $sockhost = $httpserver->read_handle->sockhost;
$sockhost = "[$sockhost]" if $sockhost =~ m/:/; # IPv6 numerical

printf "Listening on %s://%s:%d\n",
   "http",
   $sockhost, $httpserver->read_handle->sockport;

$loop->run;
