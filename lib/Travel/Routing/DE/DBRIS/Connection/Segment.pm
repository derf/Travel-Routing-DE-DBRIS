package Travel::Routing::DE::DBRIS::Connection::Segment;

use strict;
use warnings;
use 5.020;

use parent 'Class::Accessor';

use DateTime::Duration;

our $VERSION = '0.01';

Travel::Routing::DE::DBRIS::Connection::Segment->mk_ro_accessors(
	qw(
	  dep_name dep_eva arr_name arr_eva
	  train train_long train_mid train_short direction
	  sched_dep rt_dep dep
	  sched_arr rt_arr arr
	  sched_duration rt_duration duration duration_percent
	  journey_id
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

	if ( my $d = $json->{abschnittsDauerInSeconds} ) {
		$ref->{sched_duration} = DateTime::Duration->new(
			hours   => int( $d / 3600 ),
			minutes => int( ( $d % 3600 ) / 60 ),
			seconds => $d % 60,
		);
	}
	if ( my $d = $json->{ezAbschnittsDauerInSeconds} ) {
		$ref->{rt_duration} = DateTime::Duration->new(
			hours   => int( $d / 3600 ),
			minutes => int( ( $d % 3600 ) / 60 ),
			seconds => $d % 60,
		);
	}
	$ref->{duration} = $ref->{rt_duration} // $ref->{sched_duration};

	bless( $ref, $obj );

	return $ref;
}

1;
