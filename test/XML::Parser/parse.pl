use strict;
use XML::Parser;
#use YAML;
use encoding 'utf8';

my $parser = XML::Parser->new(
	Style => 'Tree'
);

my $xml = $parser->parsefile('land.xml');

print $xml;
#print @{ @{ $xml }[1] };

#local $YAML::Indent = 8;
#print Dump($xml);
