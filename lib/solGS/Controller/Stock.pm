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


=head1 PRIVATE ACTIONS

=head2 solgs_download_phenotypes

=cut


sub solgs_download_phenotypes : Path('/solgs/phenotypes') Args(1) {
     my ($self, $c, $stock_id ) = @_; # stock should be population type only?
    if ($stock_id) {
        my $stock = $self->schema->resultset('Stock::Stock')->find ( { stock_id => $stock_id } );
        my $tmp_dir = $c->get_conf('basepath') . "/" . $c->get_conf('stock_tempfiles');
        my $file_cache = Cache::File->new( cache_root => $tmp_dir  );
        $file_cache->purge();
        my $key = "stock_" . $stock_id . "_phenotype_data";
        my $phen_file = $file_cache->get($key);
        my $filename = $tmp_dir . "/stock_" . $stock_id . "_plot_phenotypes.csv";
        unless ( -e $phen_file) {
            my $phen_hashref; #hashref of hashes for the phenotype data
            my %cvterms ; #hash for unique cvterms
            ##############
            # we assume here that all phentypes are loaded on a plot level (population ->HAS accesions -> HAVE plot/s )

            my $phenotypes  =  $self->schema->resultset("Stock::Stock")->stock_project_phenotypes($stock);
            ##################
            #these are phentypes of the accessions, if $stock is a population type
            my $subjects = $stock->search_related('stock_relationship_objects')
                ->search_related('subject');
            my $subject_phenotypes  =  $self->schema->resultset("Stock::Stock")->stock_project_phenotypes($subjects);
            #these are phenotypes of the plots if $stock is a population. Typically only plots will have phenotype scores.
            my $sub_subjects = $subjects->search_related('stock_relationship_objects')
                ->search_related('subject');
            my $sub_subject_phenotypes  =  $self->schema->resultset("Stock::Stock")->stock_project_phenotypes($sub_subjects);

            my %all_phenotypes = (%$phenotypes, %$subject_phenotypes, %$sub_subject_phenotypes);
            my $replicate = 1;
            my ($replicateprop) =  $stock->search_related(
                'stockprops', {
                    'type.name' => 'replicate'
                }, { join => 'type' } );

            foreach my $project_desc (keys %all_phenotypes ) {
                my $project = $all_phenotypes{$project_desc}->{project} ;
                my $phenotype_rs = $all_phenotypes{$project_desc}->{phenotypes} ;
                my $replicate = 1;
		my $cvterm_name;
		my @sorted_phen = sort { $a->observable->name cmp $b->observable->name } $phenotype_rs->all if $phenotype_rs ;
		foreach my $ph  (@sorted_phen) {
                    my ($nd_experiment) = $ph->search_related('nd_experiment_phenotypes')->search_related('nd_experiment');
                    #add optional filter for location
                    my $geolocation = $nd_experiment->nd_geolocation;
                    #add optional filter by year/s
                    my ($yearprop) =  $project->search_related(
                        'projectprops', {
                            'type.name' => 'project year' #make sure this semantics is used for all projects
                        }, { join => 'type' } );
                    my $year = $yearprop->value if $yearprop;
                    #####
                    my ($phen_stock) = $nd_experiment->search_related('nd_experiment_stocks')->search_related('stock');
		    my $cvterm = $ph->observable;
		    if ($cvterm_name eq $cvterm->name) { $replicate ++ ; } else { $replicate = 1 ; }
                    $cvterms{$cvterm->name} = $cvterm->dbxref->db->name . ":" . $cvterm->dbxref->accession;
                    my $accession = $cvterm->dbxref->accession;
                    my $db_name = $cvterm->dbxref->db->name;
		    my $hash_key = $project_desc . "|" . $replicate ; ##$phen_stock->uniquename . "|" . $replicate  ;
		    $phen_hashref->{$hash_key}{replicate} = $replicate;
		    $cvterm_name = $cvterm->name;
		    $phen_hashref->{$hash_key}{uniquename} =  $ph->uniquename;
                    $phen_hashref->{$hash_key}{$cvterm->name} = $ph->value;
                    $phen_hashref->{$hash_key}{accession} = $db_name . ":" . $accession ;
                    $phen_hashref->{$hash_key}{year} = $year ;  ### add filter by year
                    $phen_hashref->{$hash_key}{project} = $project_desc;
                    $phen_hashref->{$hash_key}{stock} = $phen_stock->uniquename;
                    $phen_hashref->{$hash_key}{stock_id} = $phen_stock->stock_id;
                }
            }
            #write the header for the file
            write_file( $filename, ("uniquename\tstock_id\tstock_name\t" ) ) ;
            foreach my $term_name (sort { $cvterms{$a} cmp $cvterms{$b} } keys %cvterms )  {# sort ontology terms
                my $ontology_id = $cvterms{$term_name};
                write_file( $filename, {append => 1 }, ( $ontology_id . "|" . $term_name . "\t") ) ;
            }
            foreach my $key ( sort keys %$phen_hashref ) {
                #print the unique key (row header)
                # print some more columns with metadata
                # print the value by cvterm name
                write_file( $filename, {append => 1 }, ( "\n" , $key, "\t" ,$phen_hashref->{$key}{stock_id}, "\t", $phen_hashref->{$key}{stock}, "\t" ) ) ;
                foreach my $term_name ( sort { $cvterms{$a} cmp $cvterms{$b} } keys %cvterms ) {
                    write_file( $filename, {append => 1 }, ( $phen_hashref->{$key}{$term_name}, "\t" ) );
                }
            }
            $file_cache->set( $key, $filename, '30 days' );
            $phen_file = $file_cache->get($key);
        }
        my @data;
        foreach ( read_file($filename) ) {
            push @data, [ split(/\t/) ];
        }
        $c->stash->{'csv'}={ data => \@data};
        $c->forward("View::Download::CSV");
        #stock    repeat	experiment	year	SP:0001	SP:0002
    }
}



=head2 download_genotypes

=cut


sub download_genotypes : Path('genotypes') Args(1) {
    my ($self, $c, $stock_id ) = @_;
    my $stock = $c->stash->{stock_row};
    my $stock_id = $stock->stock_id;
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
