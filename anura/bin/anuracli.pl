#!/usr/bin/perl

use strict;
use warnings;

use Net::Anura;

my $wikipedia = Net::Anura->new(
	wiki => 'http://en.wikipedia.org/wiki',
	username => 'username',
	password => 'password'
);

my ($art) = $wikipedia->get( 'Color vision' );
die if ( ! defined( $art ) );

my $zive = Net::Anura->new(
	wiki => 'http://wiki.zive.ca/wiki',
	username => 'username',
	password => 'password'
);
#print $zive->put( $art );
print $zive->put( $art->title, $art->revision->text, 'Transwiki: ' . $art->revision->comment ), "\n";
