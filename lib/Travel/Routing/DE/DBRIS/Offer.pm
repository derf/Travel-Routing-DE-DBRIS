package Travel::Routing::DE::DBRIS::Offer;

use strict;
use warnings;
use 5.020;
use utf8;

use parent 'Class::Accessor';

our $VERSION = '0.03';

Travel::Routing::DE::DBRIS::Offer->mk_ro_accessors(
	qw(class name price price_unit));

sub new {
	my ( $obj, %opt ) = @_;

	my $json = $opt{json};

	my $ref = {
		class      => $json->{klasse} =~ s{KLASSE_}{}r,
		name       => $json->{name},
		price      => $json->{preis}{betrag},
		price_unit => $json->{preis}{waehrung},
		conditions => $json->{konditionsAnzeigen},
	};

	bless( $ref, $obj );

	return $ref;
}

sub conditions {
	my ($self) = @_;

	return @{ $self->{conditions} // [] };
}

1;
