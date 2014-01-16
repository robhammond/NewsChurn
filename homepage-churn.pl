#!/usr/bin/env perl
use strict;
use warnings;
use Modern::Perl;
use MongoDB;
use MongoDB::OID;
use AnyEvent;
use AnyEvent::HTTP;
use Mojo::Log;
use Mojo::Util qw(decode encode html_unescape xml_escape);
use Mojo::DOM;
use Mojo::URL;
use Data::Dumper;

my $log = Mojo::Log->new;

my $user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/32.0.1700.77 Safari/537.36';

my $client   = MongoDB::Connection->new(host => 'localhost', port => 27017);
my $db       = $client->get_database( 'homepage_churn' );
my $churn    = $db->get_collection( 'churn' );

# {
# 	url => url,
# 	time => time,
# 	links => [
# 		{href => href, text => text, position => 1},
# 		...
# 	],
# 	text => '',
# }

my $cv = AE::cv;

my $result;

my @urls = qw(http://www.telegraph.co.uk/
http://www.theguardian.com/uk
http://www.mirror.co.uk/
http://www.dailymail.co.uk/home/index.html
http://www.independent.co.uk/
http://www.thesun.co.uk/sol/homepage/
http://www.thetimes.co.uk/tto/news/
http://www.ft.com/home/uk
http://www.nytimes.com/
http://www.bbc.co.uk/);

my @screens;

for my $url (@urls) {
    $cv->begin;
    my $now = time;
    my $request;
    $log->info("fetching $url");
    my $mojo_url = Mojo::URL->new($url);
    
    $request = http_request(
        GET => $url,
        timeout => 120, # seconds
        recurse => 5, # redirects
        headers => { "user-agent" => $user_agent },
        sub {
            my ($body, $hdr) = @_;

            # only index successful responses and a limited set of content types
	        if ($hdr->{Status} =~ /^2/) {
                my $content = $body;
                
                my ($charset) = $hdr->{'content-type'} =~ /charset=([-0-9A-Za-z]+)$/; 
                
                # attempt to decode content
                if ($charset) {
                    $charset =~ s!utf-8!utf8!;
                    $content = decode($charset, $body);
                }

                # remove junk content
                $content =~ s!<(script|style|iframe|meta|embed|link)[^>]*>.*?</\1>!!gis;

                # initialise DOM parser
                my $dom = Mojo::DOM->new($content);
                my @links;
                my $i = 1;
                for my $e ($dom->find('a[href]')->each) {
                	my $href = Mojo::URL->new($e->{'href'})->to_abs($mojo_url);
                	push @links, { href => $href->to_string, text => $e->all_text, position => $i };
                	$i++;
                }
              
                # Turn back into DOM object to retrieve text
                my $clean_content = $dom->all_text;
                $clean_content =~ s![<>]!!g;
                $clean_content =~ s!\s+! !gs;
                $clean_content =~ s!\n+! !gs;
                
                my $ts = time();

                my $id = _insert_data({
                	url => $url,
                	time => $ts,
                	links => \@links,
                	text => $clean_content,	
            	});

                open(HTML,">:utf8", "cache/$id.html" ) or die $!;
                print HTML $body;
                close HTML;

                # _fetch_screengrab($url, $id);
                push @screens, {url => $url, id => $id};

            } else {
	            $log->error(
			     "Error for ",
			       $url,
			       ": (", 
			       $hdr->{Status}, 
			       ") ", 
			       $hdr->{Reason},
			       Dumper($hdr)
			       );
	        }
            undef $request;
            $cv->end;
        }
    );
}

$cv->wait;

# fetch screengrabs after loop as causes timeout errors otherwise
for my $s (@screens) {
    _fetch_screengrab($s->{'url'}, $s->{'id'});
}

sub _insert_data {
    my $data = shift;
    # checking out URL for indexing
    my $id = $churn->insert($data);
    return $id;
}

sub _fetch_screengrab {
	my ($url, $id) = @_;
	$log->info("grabbing $url");
	system("casperjs screen.js --url=$url --id=$id");
	return 1;
}