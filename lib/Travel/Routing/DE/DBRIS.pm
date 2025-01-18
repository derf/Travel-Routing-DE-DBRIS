package Travel::Routing::DE::DBRIS;

# vim:foldmethod=marker

use strict;
use warnings;
use 5.020;
use utf8;

use parent 'Class::Accessor';

use Carp qw(confess);
use DateTime;
use DateTime::Format::Strptime;
use Encode qw(decode encode);
use JSON;
use LWP::UserAgent;
use Travel::Status::DE::DBRIS;
use Travel::Routing::DE::DBRIS::Connection;

our $VERSION = '0.01';

Travel::Routing::DE::DBRIS->mk_ro_accessors(qw(earlier later));

# {{{ Constructors

sub new {
	my ( $obj, %conf ) = @_;
	my $service = $conf{service};

	my $ua = $conf{user_agent};

	if ( not $ua ) {
		my %lwp_options = %{ $conf{lwp_options} // { timeout => 10 } };
		$ua = LWP::UserAgent->new(%lwp_options);
		$ua->env_proxy;
	}

	my $self = {
		developer_mode => $conf{developer_mode},
		results        => [],
		from           => $conf{from},
		to             => $conf{to},
		ua             => $ua,
	};

	bless( $self, $obj );

	my $dt = $conf{datetime} // DateTime->now( time_zone => 'Europe/Berlin' );
	my @mots
	  = (qw(ICE EC_IC IR REGIONAL SBAHN BUS SCHIFF UBAHN TRAM ANRUFPFLICHTIG));
	if ( $conf{modes_of_transit} ) {
		@mots = @{ $conf{modes_of_transit} // [] };
	}

	my $req = {
		abfahrtsHalt     => $conf{from}->id,
		ankunftsHalt     => $conf{to}->id,
		anfrageZeitpunkt => $dt->strftime('%Y-%m-%dT%H:%M:00'),
		ankunftSuche     => 'ABFAHRT',
		klasse           => 'KLASSE_2',
		produktgattungen => \@mots,
		reisende         => [
			{
				typ            => 'ERWACHSENER',
				ermaessigungen => [
					{
						art    => 'KEINE_ERMAESSIGUNG',
						klasse => 'KLASSENLOS'
					},
				],
				alter  => [],
				anzahl => 1,
			}
		],
		schnelleVerbindungen              => \1,
		sitzplatzOnly                     => \0,
		bikeCarriage                      => \0,
		reservierungsKontingenteVorhanden => \0,
		nurDeutschlandTicketVerbindungen  => \0,
		deutschlandTicketVorhanden        => \0
	};

	if ( @{ $conf{discount} // [] } ) {
		$req->{reisende}[0]{ermaessigungen} = [];
	}
	for my $discount ( @{ $conf{discounts} // [] } ) {
		my ( $type, $class );
		for my $num (qw(25 50 100)) {
			if ( $discount eq "bc${num}" ) {
				$type  = "BAHNCARD${num}";
				$class = 'KLASSE_2';
			}
			elsif ( $discount eq "bc${num}-first" ) {
				$type  = "BAHNCARD${num}";
				$class = 'KLASSE_1';
			}
		}
		if ($type) {
			push(
				@{ $req->{reisende}[0]{ermaessigungen} },
				{
					art    => $type,
					klasse => $class,
				}
			);
		}
	}

	$self->{strptime_obj} //= DateTime::Format::Strptime->new(
		pattern   => '%Y-%m-%dT%H:%M:%S',
		time_zone => 'Europe/Berlin',
	);

	$self->{strpdate_obj} //= DateTime::Format::Strptime->new(
		pattern   => '%Y-%m-%d',
		time_zone => 'Europe/Berlin',
	);

	my $json = $self->{json} = JSON->new->utf8;

	if ( $conf{async} ) {
		$self->{req} = $req;
		return $self;
	}

	if ( $conf{json} ) {
		$self->{raw_json} = $conf{json};
	}
	else {
		my $req_str = $json->encode($req);
		if ( $self->{developer_mode} ) {
			say "requesting $req_str";
		}

		my ( $content, $error )
		  = $self->post_with_cache(
			'https://www.bahn.de/web/api/angebote/fahrplan', $req_str );

		if ($error) {
			$self->{errstr} = $error;
			return $self;
		}

		if ( $self->{developer_mode} ) {
			say decode( 'utf-8', $content );
		}

		$self->{raw_json} = $json->decode($content);
		$self->parse_connections;
	}

	return $self;
}

sub new_p {
	my ( $obj, %conf ) = @_;
	my $promise = $conf{promise}->new;

	if (
		not(    $conf{from}
			and $conf{to} )
	  )
	{
		return $promise->reject('"from" and "to" opts are mandatory');
	}

	my $self = $obj->new( %conf, async => 1 );
	$self->{promise} = $conf{promise};

	$self->post_with_cache_p( $self->{url} )->then(
		sub {
			my ($content) = @_;
			$self->{raw_json} = $self->{json}->decode($content);
			$self->parse_connections;
			$promise->resolve($self);
			return;
		}
	)->catch(
		sub {
			my ($err) = @_;
			$promise->reject( $err, $self );
			return;
		}
	)->wait;

	return $promise;
}

# }}}
# {{{ Internal Helpers

sub post_with_cache {
	my ( $self, $url, $req ) = @_;
	my $cache = $self->{cache};

	if ( $self->{developer_mode} ) {
		say "POST $url $req";
	}

	if ($cache) {
		my $content = $cache->thaw($url);
		if ($content) {
			if ( $self->{developer_mode} ) {
				say '  cache hit';
			}
			return ( ${$content}, undef );
		}
	}

	if ( $self->{developer_mode} ) {
		say '  cache miss';
	}

	my $reply = $self->{ua}->post(
		$url,
		Accept           => 'application/json',
		'Content-Type'   => 'application/json; charset=utf-8',
		Origin           => 'https://www.bahn.de',
		Referer          => 'https://www.bahn.de/buchung/fahrplan/suche',
		'Sec-Fetch-Dest' => 'empty',
		'Sec-Fetch-Mode' => 'cors',
		'Sec-Fetch-Site' => 'same-origin',
		TE               => 'trailers',
		Content          => $req,
	);

	if ( $reply->is_error ) {
		say $reply->status_line;
		return ( undef, $reply->status_line );
	}
	my $content = $reply->content;

	if ($cache) {
		$cache->freeze( $url, \$content );
	}

	return ( $content, undef );
}

sub post_with_cache_p {
	...;
}

sub parse_connections {
	my ($self) = @_;

	my $json = $self->{raw_json};

	$self->{earlier} = $json->{verbindungReference}{earlier};
	$self->{later}   = $json->{verbindungReference}{later};

	for my $connection ( @{ $json->{verbindungen} // [] } ) {
		push(
			@{ $self->{connections} },
			Travel::Routing::DE::DBRIS::Connection->new(
				json         => $connection,
				strpdate_obj => $self->{strpdate_obj},
				strptime_obj => $self->{strptime_obj}
			)
		);
	}
}

# }}}
# {{{ Public Functions

sub errstr {
	my ($self) = @_;

	return $self->{errstr};
}

sub connections {
	my ($self) = @_;
	return @{ $self->{connections} };
}

# }}}

1;
