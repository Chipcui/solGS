package solGS::Controller::Stock;

=head1 NAME

solGS::Controller::Stock - Catalyst controller for phenotyping and genotyping data related to stocks (e.g. accession, plot, population, etc.)

=cut

use Moose;
use namespace::autoclean;
use YAML::Any qw/LoadFile/;

use URI::FromHash 'uri';
use List::Compare;
use File::Temp qw / tempfile /;
use File::Slurp;
use JSON::Any;


BEGIN { extends 'Catalyst::Controller' }
with 'Catalyst::Component::ApplicationAttribute';

has 'schema' => (
    is       => 'rw',
    isa      => 'DBIx::Class::Schema',
    lazy_build => 1,
);

sub _build_schema {
    shift->_app->dbic_schema( 'Bio::Chado::Schema', 'sgn_chado' )
}

sub validate_stock_list {
    my ($self, $c) = shift;
    #check here the list of submitted stocks

    my $stock_names; #array ref of names - convert all to lower case ?
    #search the stock table and return error message if some stocks were not found
    my $stock_rs = $self->schema->resultset('Stock::Stock' , {
        -or => [
             'lower(me.name)' => { -in => $stock_names } ,
             'lower(me.uniquename)' => { -in => $stock_names },
             -and => [
                 'lower(type.name)' => { like =>'%synonym%' },
                 'lower(stockprops.value)' => { -in => $stock_names  },
             ],
            ],
           } ,
           {  join =>  { 'stockprops' =>  'type'  }  ,
              columns => [ qw/stock_id uniquename type_id organism_id / ],
              distinct => 1
           }
        );
    $self->_filter_stock_rs($c,$stock_rs);

}
# select stock_rs for genomic selection tool
sub _filter_stock_rs {
    my ( $self, $c, $rs ) = @_;

    # filter by genoytpe and phenotype experiments
    $rs = $rs->search(
        {
            'type.name' => 'phenotyping experiment'
        } ,
        { join => {nd_experiment_stocks => { nd_experiment => { 'type' } } } ,
          distinct => 1
        } );

    $rs = $rs->search(
        {
            'type.name' => 'genotyping experiment'
        } ,
        { join => {nd_experiment_stocks => { nd_experiment => { 'type' } } } ,
          distinct => 1
        } );

    # optional - filter by project name , project year, location
    if( my $project_name = $c->req->param('project_name') ) {
        # filter by multiple project names
    }


    return $rs;
}


__PACKAGE__->meta->make_immutable;
