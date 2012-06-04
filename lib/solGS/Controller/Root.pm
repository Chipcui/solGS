package solGS::Controller::Root;
use Moose;
use namespace::autoclean;
use URI::FromHash 'uri';
use File::Path qw / mkpath  /;
use File::Spec::Functions qw / catfile catdir/;
use File::Temp qw / tempfile tempdir /;
use Cache::File;
use Try::Tiny;
use Scalar::Util 'weaken';
use CatalystX::GlobalContext ();

use CXGN::Login;
use CXGN::People::Person;
use CXGN::Tools::Run;

BEGIN { extends 'Catalyst::Controller::HTML::FormFu' }

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#

__PACKAGE__->config(namespace => '');

=head1 NAME

solGS::Controller::Root - Root Controller for solGS

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=head2 index

The root page (/)

=cut


sub index :Path :Args(0) {
    my ($self, $c) = @_; 
    $c->stash(template=>'home.mas')
}


sub submit :Path('/submit/intro') :Args(0) {
    my ($self, $c) = @_;
    $c->stash(template=>'/submit/intro.mas');
}

sub details_form : Path('/form/population/details') Args(0) FormConfig('population/details.yml')  {
    my ($self, $c) = @_;
    my $form = $c->stash->{form}; 
   
    if ($form->submitted_and_valid ) 
    {
        $c->res->redirect('/form/population/phenotype');
    }
    else 
    {
        $c->stash(template =>'/form/population/details.mas',
                  form     => $form
            );
    }
}

sub phenotype_form : Path('/form/population/phenotype') Args(0) FormConfig('population/phenotype.yml') {
    my ($self, $c) = @_;
    my $form = $c->stash->{form};

    if ($form->submitted_and_valid) 
    {
      $c->res->redirect('/form/population/genotype');
    }        
    else
    {
        $c->stash(template => '/form/population/phenotype.mas',
                  form     => $form
            );
    }

}


sub genotype_form : Path('/form/population/genotype') Args(0) FormConfig('population/genotype.yml') {
    my ($self, $c) = @_;
    my $form = $c->stash->{form};

    if ($form->submitted_and_valid) 
    {
      $c->res->redirect('/population/12');
    }        
    else
    {
        $c->stash(template => '/form/population/genotype.mas',
                  form     => $form
            );
    }

}

sub search : Path('/search/solgs') Args() FormConfig('search/solgs.yml') {
    my ($self, $c) = @_;
    my $form = $c->stash->{form};
    
    my $query;
    if ($form->submitted_and_valid) 
    {
        $query = $form->param_value('search.search_term');
        $c->res->redirect("/search/result/traits/$query");       
    }        
    else
    {
        $c->stash(template => '/search/solgs.mas',
                  form     => $form,
                  message  => $query
            );
    }

}

sub show_search_result_pops : Path('/search/result/populations') Args(1) {
    my ($self, $c, $query) = @_;
  
    my $pop_ids = $c->model('solGS')->search_populations($c, $query);
  
    my (@result, @unique_ids);
    foreach my $pop_id (@$pop_ids) 
    {      
        unless (grep {$_ == $pop_id} @unique_ids) 
        {
            push @unique_ids, $pop_id;        
            my $pop_rs   = $c->model('solGS')->get_population_details($c, $pop_id);
            my $pop_name = $pop_rs->single->name;
            push @result, [qq|<a href="/population/$pop_id">$pop_name</a>|, 'loc', 2012, $pop_id]; 
        }
    }

    my $form;
    if (@$pop_ids[0])
    {
       $c->stash(template => '/search/result/populations.mas',
                 result   => \@result,
                 form     => $form
           );
    }
    else
    {
        $c->res->redirect('/search/solgs');     
    }

}

sub show_search_result_traits : Path('/search/result/traits') Args(1)  FormConfig('search/solgs.yml'){
    my ($self, $c, $query) = @_;
  
    my @rows;
    my $result = $c->model('solGS')->search_trait($c, $query);
 
    while (my $row = $result->next)
    {
        my $id   = $row->cvterm_id;
            my $name = $row->name;
            my $def  = $row->definition;
            my $checkbox = qq |<form> <input type="checkbox" name="trait" value="$name" /> </form> |;
       
            push @rows, [ $checkbox, qq |<a href="/search/result/populations/$id">$name</a>|, $def];      
    }

    if (@rows)
    {
       $c->stash(template   => '/search/result/traits.mas',
                 result     => \@rows,
                 query      => $query,
                 pager      => $result->pager,
                 page_links => sub {uri ( query => { trait => $query, page => shift } ) }
           );
    }
    else
    {
        my $form = $c->stash->{form};
        $c->stash(template => '/search/solgs.mas',
                  form     => $form,
                  message  => $query
            );  
    }

}    
sub population :Path('/population') Args(1) {
    my ($self, $c, $pop_id) = @_;
    $c->stash(template => '/population.mas',
              pop_id   => $pop_id
        );
}

sub input_files :Private {
    my ($self, $c, $pop_id) = @_;
    $self->genotype_file($c, $pop_id);
    $self->phenotype_file($c, $pop_id);
    my $pheno_file = $c->stash->{phenotype_file};
    my $geno_file = $c->stash->{genotype_file};
 
   # my $trait_file = $self->trait_file;
}

sub output_files :Private {
    my ($self, $c, $pop_id, $trait_id) = @_;
    my $trait = $self->get_trait_name($c, $trait_id);
    $trait = $self->abbreviate_term($trait);
   
    $self->gebv_kinship_file($c, $trait, $pop_id);
    $self->gebv_marker_file($c, $trait, $pop_id);
    
    my $file_list = join ("\t",
                          $c->stash->{gebv_kinship_file},
                          $c->stash->{gebv_marker_file}
        );
                          
    my $tmp_dir = $c->stash->{solgs_tempfiles_dir};

    my ($fh, $tempfile) = tempfile("output_files_${trait}_$pop_id-XXXXX", DIR => $tmp_dir);
    $fh->print($file_list);
    
    return $tempfile;

}

sub abrreviate_term {
    my ($self, $term) = @_;
  
    my @words = split(/\s/, $term);
    my $acronym;
	
    if (scalar(@words) == 1) 
    {
	$acronym .= shift(@words);
    }  
    else 
    {
	foreach my $word (@words) 
        {
	    if ($word=~/^\D/)
            {
		my $l = substr($word,0,1,q{}); 
		$acronym .= $l;
	    } 
            else 
            {
                $acronym .= $word;
            }
	    $acronym = uc($acronym);
	    $acronym =~/(\w+)/;
	    $acronym = $1;
	}	   
    }
    return $acronym;

}

sub gebv_marker_file {
    my ($self, $c, $pop_id, $trait) = @_;
   
    my $solgs_cache = $c->stash->{solgs_cache};
    my $file_cache  = Cache::File->new(cache_root => $solgs_cache);
    $file_cache->purge();

    my $key               = "gebv_marker_" . $pop_id . "_".  $trait;
    my $gebv_marker_file  = $file_cache->get($key);

    unless ($gebv_marker_file)
    {      
        my $file = catfile($solgs_cache, "gebv_marker_" . $trait . "_" . $pop_id);
        $file_cache->set( $key, $file, '30 days' );
        $gebv_marker_file = $file_cache->get($key);
    }

    $c->stash->{gebv_marker_file} = $gebv_marker_file;
    
}

sub gebv_kinship_file {
    my ($self, $c, $pop_id, $trait) = @_;
       
    my $solgs_cache = $c->stash->{solgs_cache};
    my $file_cache  = Cache::File->new( cache_root => $solgs_cache  );
    $file_cache->purge();

    my $key                = "gebv_kinship_" . $pop_id . "_".  $trait;
    my $gebv_kinship_file  = $file_cache->get($key);

    unless ($gebv_kinship_file)
    {      
        my $file = catfile($solgs_cache, "gebv_kinship_" . $trait . "_" . $pop_id);
        $file_cache->set( $key, $file, '30 days' );
        $gebv_kinship_file = $file_cache->get($key);
    }

    $c->stash->{gebv_kinship_file} = $gebv_kinship_file;
}

sub get_trait_name {
    my ($self, $c, $trait_id) = @_;
    my $trait_name = $c->model('solGS')->trait_name($c, $trait_id);
    
    return $trait_name;
}

sub phenotype_file :Private {
    my ($self, $c, $pop_id) =@_;
    
    $c->controller('Stock')->solgs_download_phenotypes($pop_id);
    my $pheno_file = "stock_" . $pop_id . "_plot_phenotypes.csv";
     $pheno_file   =  catfile($c->config->{solgs_tempfiles}, $pheno_file);
    if (-s $pheno_file >= 100 )
    {
       
        $c->stash->{phenotype_file} = $pheno_file;
    }
    else
    {
        $c->throw_client_error( public_message => "The phenotype data file $pheno_file
                                               does not seem to contain data."
            );
    }

}

sub genotype_file :Private {
    my ($self, $c, $pop_id) =@_;
    
    $c->controller('Stock')->download_genotypes($pop_id);
    my $geno_file = "stock_" . $pop_id . "_plot_genotypes.csv";
    $geno_file    =  catfile($c->config->{solgs_tempfiles}, $geno_file);
    if (-s $geno_file >= 100 )
    {
        
        $c->stash->{genotype_file} = $geno_file;
    }
    else
    {
        $c->throw_client_error( public_message => "The genotype data file $geno_file
                                               does not seem to contain data."
            );
    }

}
sub run_rrblup  :Private {
    my ($self, $c, $pop_id, $trait_id) = @_;
    
    #get all input files & arguments for rrblup, 
    #run rrblup and save output in solgs user dir
    my $input_files  = $self->input_files($c, $pop_id, $trait_id);
    my $output_files = $self->output_files($c, $pop_id, $trait_id);
   
    CXGN::Tools::Run->temp_base($c->stash->{solgs_tempfiles});
    my ( $r_in_temp, $r_out_temp ) =
        map 
    {
            my ( undef, $filename ) =
                tempfile(
                    catfile(
                        CXGN::Tools::Run->temp_base(),
                        "gs-rrblup-$pop_id-$_-XXXXXX",
                    ),
                );
            $filename
    } qw / in out /;
    {
        my $r_cmd_file = $c->path_to('R/gs.r');
        copy($r_cmd_file, $r_in_temp)
            or die "could not copy '$r_cmd_file' to '$r_in_temp'";
    }

    try 
    {
        my $r_process = CXGN::Tools::Run->run_cluster(
            'R', 'CMD', 'BATCH',
            '--slave',
            "--args $input_files, $output_files",
            $r_in_temp,
            $r_out_temp,
            {
                working_dir => $c->stash->{solgs_tempfiles},
                max_cluster_jobs => 1_000_000_000,
            },
            );

        $r_process->wait; 
    }
    catch 
    {
        my $err = $_;
        $err =~ s/\n at .+//s; 
        try
        { 
            $err .= "\n=== R output ===\n".file($r_out_temp)->slurp."\n=== end R output ===\n" 
        };
        $c->throw_client_error(public_message    => "There was an error running rrblup.",
                               developer_message => $err
            );
    };

   #return or stash output files
}
   

sub get_solgs_dirs :Private {
    my ($self, $c) = @_;
   
    my $solgs_dir       = $c->config->{solgs_dir};
    my $solgs_cache     = catdir($solgs_dir, 'cache'); 
    my $solgs_tempfiles = catdir($solgs_dir, 'tempfiles');
  
    mkpath ([$solgs_dir, $solgs_cache, $solgs_tempfiles], 0, 0755);
      
    $c->stash(solgs_dir       => $solgs_dir, 
              solgs_cache_dir     => $solgs_cache, 
              solgs_tempfiles_dir => $solgs_tempfiles
        );

}




sub default :Path {
    my ( $self, $c ) = @_; 
    $c->forward('search');
}



=head2 end

Attempt to render a view, if needed.

=cut

sub render : ActionClass('RenderView') {}


sub end : Private {
    my ( $self, $c ) = @_;

    return if @{$c->error};

    # don't try to render a default view if this was handled by a CGI
    $c->forward('render') unless $c->req->path =~ /\.pl$/;

    # enforce a default text/html content type regardless of whether
    # we tried to render a default view
    $c->res->content_type('text/html') unless $c->res->content_type;

    # insert our javascript packages into the rendered view
    if( $c->res->content_type eq 'text/html' ) {
        $c->forward('/js/insert_js_pack_html');
        $c->res->headers->push_header('Vary', 'Cookie');
    } else {
        $c->log->debug("skipping JS pack insertion for page with content type ".$c->res->content_type)
            if $c->debug;
    }

}

=head2 auto

Run for every request to the site.

=cut

sub auto : Private {
    my ($self, $c) = @_;
    CatalystX::GlobalContext->set_context( $c );
    $c->stash->{c} = $c;
    weaken $c->stash->{c};

    $self->get_solgs_dirs($c);
    # gluecode for logins
    #
    unless( $c->config->{'disable_login'} ) {
        my $dbh = $c->dbc->dbh;
        if ( my $sp_person_id = CXGN::Login->new( $dbh )->has_session ) {

            my $sp_person = CXGN::People::Person->new( $dbh, $sp_person_id);

            $c->authenticate({
                username => $sp_person->get_username(),
                password => $sp_person->get_password(),
            });
        }
    }

    return 1;
}





=head1 AUTHOR

Isaak Y Tecle <iyt2@cornell.edu>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
