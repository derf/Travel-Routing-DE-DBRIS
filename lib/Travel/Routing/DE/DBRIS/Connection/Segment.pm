package Travel::Routing::DE::DBRIS::Connection::Segment;

use strict;
use warnings;
use 5.020;

use parent 'Class::Accessor';

use DateTime::Duration;
use Travel::Status::DE::DBRIS::Location;

our $VERSION = '0.01';

Travel::Routing::DE::DBRIS::Connection::Segment->mk_ro_accessors(
	qw(
	  dep_name dep_eva arr_name arr_eva
	  train train_long train_mid train_short direction
	  sched_dep rt_dep dep
	  sched_arr rt_arr arr
	  sched_duration rt_duration duration duration_percent
	  journey_id
	  occupancy occupancy_first occupancy_second
	  is_transfer is_walk walk_name distance_m
	)
);

sub new {
	my ( $obj, %opt ) = @_;

	my $json     = $opt{json};
	my $strptime = $opt{strptime_obj};

	my $ref = {
		arr_eva     => $json->{ankunftsOrtExtId},
		arr_name    => $json->{ankunftsOrt},
		dep_eva     => $json->{abfahrtsOrtExtId},
		dep_name    => $json->{abfahrtsOrt},
		train       => $json->{verkehrsmittel}{name},
		train_short => $json->{verkehrsmittel}{kurzText},
		train_mid   => $json->{verkehrsmittel}{mittelText},
		train_long  => $json->{verkehrsmittel}{langText},
		direction   => $json->{verkehrsmittel}{richtung},
		distance_m  => $json->{distanz},
	};

	if ( my $ts = $json->{abfahrtsZeitpunkt} ) {
		$ref->{sched_dep} = $strptime->parse_datetime($ts);
	}
	if ( my $ts = $json->{ezAbfahrtsZeitpunkt} ) {
		$ref->{rt_dep} = $strptime->parse_datetime($ts);
	}
	$ref->{dep} = $ref->{rt_dep} // $ref->{sched_dep};

	if ( my $ts = $json->{ankunftsZeitpunkt} ) {
		$ref->{sched_arr} = $strptime->parse_datetime($ts);
	}
	if ( my $ts = $json->{ezAnkunftsZeitpunkt} ) {
		$ref->{rt_arr} = $strptime->parse_datetime($ts);
	}
	$ref->{arr} = $ref->{rt_arr} // $ref->{sched_arr};

	# PUBLICTRANSPORT uses abschnittsDauerInSeconds; WALK uses abschnittsDauer
	if ( my $d = $json->{abschnittsDauerInSeconds} // $json->{abschnittsDauer} )
	{
		$ref->{sched_duration} = DateTime::Duration->new(
			hours   => int( $d / 3600 ),
			minutes => int( ( $d % 3600 ) / 60 ),
			seconds => $d % 60,
		);
	}
	if ( my $d = $json->{ezAbschnittsDauerInSeconds}
		// $json->{ezAbschnittsDauer} )
	{
		$ref->{rt_duration} = DateTime::Duration->new(
			hours   => int( $d / 3600 ),
			minutes => int( ( $d % 3600 ) / 60 ),
			seconds => $d % 60,
		);
	}
	$ref->{duration} = $ref->{rt_duration} // $ref->{sched_duration};

	for my $occupancy ( @{ $json->{auslastungsmeldungen} // [] } ) {
		if ( $occupancy->{klasse} eq 'KLASSE_1' ) {
			$ref->{occupancy_first} = $occupancy->{stufe};
		}
		if ( $occupancy->{klasse} eq 'KLASSE_2' ) {
			$ref->{occupancy_second} = $occupancy->{stufe};
		}
	}

	if ( $ref->{occupancy_first} and $ref->{occupancy_second} ) {
		$ref->{occupancy}
		  = ( $ref->{occupancy_first} + $ref->{occupancy_second} ) / 2;
	}
	elsif ( $ref->{occupancy_first} ) {
		$ref->{occupancy} = $ref->{occupancy_first};
	}
	elsif ( $ref->{occupancy_second} ) {
		$ref->{occupancy} = $ref->{occupancy_second};
	}

	for my $stop ( @{ $json->{halte} // [] } ) {
		push(
			@{ $ref->{route} },
			Travel::Status::DE::DBRIS::Location->new(
				json         => $stop,
				strptime_obj => $strptime
			)
		);
	}

	if ( $json->{verkehrsmittel}{typ} eq 'WALK' ) {
		$ref->{is_walk}   = 1;
		$ref->{walk_name} = $json->{verkehrsmittel}{name};
	}
	if ( $json->{verkehrsmittel}{typ} eq 'TRANSFER' ) {
		$ref->{is_transfer} = 1;
		$ref->{transfer_notes}
		  = [ map { $_->{value} } @{ $json->{transferNotes} // [] } ];
	}

	bless( $ref, $obj );

	return $ref;
}

sub route {
	my ($self) = @_;

	return @{ $self->{route} // [] }[ 1 .. $#{ $self->{route} } - 1 ];
}

sub transfer_notes {
	my ($self) = @_;

	return @{ $self->{transfer_notes} // [] };
}

1;
