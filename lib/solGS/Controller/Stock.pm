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
use  Bio::Chado::NaturalDiversity::Reports;

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
    if( my $project_ids = $c->req->param('projects') ) {
        # filter by multiple project names select box should allow selecting of multiple
        # project names. Value is a listref of project_ids
        $rs = $rs->search(
            { 'project.project_id' => { -in =>  $project_ids },
            },
            { join => { nd_experiment_stocks => { nd_experiment => { 'nd_experiment_project' => 'project'  }}},
              distinct => 1
            } );
    }
    if (my $years = $c->req->param('years') ) {
        # filter by multiple years. param is a listref of values
        $rs = $rs->search(
            { 'projectprop.value' => { -in =>  $years },
              'lower(type.name)' => { like => '%year%' }
            },
            { join => { nd_experiment_stocks => { nd_experiment => { 'nd_experiment_project' =>  { 'project' =>  { 'projectprops' => 'type' }}}}},
              distinct => 1
            });
    }
    if( my $location_ids = $c->req->param('locations') ) {
        # filter by multiple locations. param is listref of nd_geolocation_ids
        $rs = $rs->search(
            { 'nd_experiment.nd_geolocation_id' => { -in =>  $location_ids },
            },
            { join => { nd_experiment_stocks => ' nd_experiment' },
              distinct => 1
            });
    }
    return $rs;
}


=head1 PRIVATE ACTIONS

=head2 solgs_download_phenotypes

=cut


sub solgs_download_phenotypes : Path('/solgs/phenotypes') Args(1) {
    my ($self, $c, $stock_id ) = @_; # stock should be population type only?
    
    if ($stock_id) {
        
        $c->stash->{pop_id} = $stock_id;
        $c->controller('Root')->phenotype_file($c);
        
        my $d = read_file($c->stash->{phenotype_file});
              
        my @info  = split(/\n/ , $d);
        my @data;
       
        foreach (@info) {
            push @data, [ split(/\t/) ] ;
        }
        
        $c->stash->{'csv'}={ data => \@data};
        $c->forward("View::Download::CSV");
    }
}


=head2 download_genotypes

=cut


sub download_genotypes : Path('genotypes') Args(1) {
    my ($self, $c, $stock_id ) = @_;
    my $stock = $c->stash->{stock_row};
    $stock_id = $stock->stock_id;
    my $stock_name = $stock->uniquename;
    if ($stock_id) {
        my $tmp_dir = $c->get_conf('basepath') . "/" . $c->get_conf('stock_tempfiles');
        my $file_cache = Cache::File->new( cache_root => $tmp_dir  );
        $file_cache->purge();
        my $key = "stock_" . $stock_id . "_genotype_data";
        my $gen_file = $file_cache->get($key);
        my $filename = $tmp_dir . "/stock_" . $stock_id . "_genotypes.csv";
        unless ( -e $gen_file) {
            my $gen_hashref; #hashref of hashes for the phenotype data
            my %cvterms ; #hash for unique cvterms
            ##############
            my $genotypes =  $self->_stock_project_genotypes( $stock );
            write_file($filename, ("project\tmarker\t$stock_name\n") );
            foreach my $project (keys %$genotypes ) {
                #my $genotype_ref = $genotypes->{$project} ;
                #my $replicate = 1;
		foreach my $geno (@ { $genotypes->{$project} } ) {
		    my $genotypeprop_rs = $geno->search_related('genotypeprops', {
			#this is the current genotype we have , add more here as necessary
			'type.name' => 'infinium array' } , {
			    join => 'type' } );
		    while (my $prop = $genotypeprop_rs->next) {
			my $json_text = $prop->value ;
			my $genotype_values = JSON::Any->decode($json_text);
			foreach my $marker_name (keys %$genotype_values) {
			    my $read = $genotype_values->{$marker_name};
			    write_file( $filename, { append => 1 } , ($project, "\t" , $marker_name, "\t", $read, "\n") );
			}
		    }
		}
	    }
            $file_cache->set( $key, $filename, '30 days' );
            $gen_file = $file_cache->get($key);
        }
        my @data;
        foreach ( read_file($filename) ) {
            push @data, [ split(/\t/) ];
        }
        $c->stash->{'csv'}={ data => \@data};
        $c->forward("View::Download::CSV");
    }
}

__PACKAGE__->meta->make_immutable;
