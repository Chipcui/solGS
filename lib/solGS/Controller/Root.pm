package solGS::Controller::Root;

use Moose;
use namespace::autoclean;

use String::CRC;
use URI::FromHash 'uri';
use File::Path qw / mkpath  /;
use File::Spec::Functions qw / catfile catdir/;
use File::Temp qw / tempfile tempdir /;
use File::Slurp qw /write_file read_file :edit prepend_file/;
use File::Copy;
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
    my ($self, $c, $trait_id) = @_;
  
    my $pop_ids = $c->model('solGS')->search_populations($c, $trait_id);
  
    my (@result, @unique_ids);
   
    
    my $form;
    if (@$pop_ids[0])
    {
        foreach my $pop_id (@$pop_ids) 
        {      
            unless (grep {$_ == $pop_id} @unique_ids) 
            {
                push @unique_ids, $pop_id;        
                my $pop_rs   = $c->model('solGS')->get_population_details($c, $pop_id);
                my $pop_name = $pop_rs->single->name;
                push @result, [qq|<a href="/trait/$trait_id/population/$pop_id">$pop_name</a>|, 'loc', 2012, $pop_id]; 
            }
        }
        
        $self->get_trait_name($c, $trait_id);
       
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
   
    if ($pop_id )
    {   
        $c->stash->{pop_id} = $pop_id;  
        $self->phenotype_file($c);
        #$self->genotype_file($c);
        $self->get_all_traits($c);
       
        $c->stash->{template} = '/population.mas';
        $c->stash->{no_traits_selected} = 'choose' if ($c->stash->{referer} !~ /analyze\/traits\/population/);
        $self->select_traits($c);
    }
    else 
    {
        $c->throw(public_message =>"Required population id is missing.", 
                  is_client_error => 1, 
            );
    }
} 

sub select_traits   {
    my ($self, $c) = @_;
    my $traits_form = $self->form;
    $traits_form->load_config_file('population/traits.yml');
    
    $c->stash->{traits_form} = $traits_form;
 
}

sub trait :Path('/trait') Args(3) {
    my ($self, $c, $trait_id, $key, $pop_id) = @_;
   
    if ($pop_id && $trait_id)
    {   
        $self->get_trait_name($c, $trait_id);
        $c->stash->{pop_id} = $pop_id;
                      
        $self->get_rrblup_output($c);
        $self->gs_files($c);

        $c->stash->{template} = "/population/trait.mas";
    }
    else 
    {
        $c->throw(public_message =>"Required population id or/and trait id are missing.", 
                  is_client_error => 1, 
            );
    }
}

sub gs_files {
    my ($self, $c) = @_;
    
    $self->output_files($c);
    $self->model_accuracy($c);
    $self->blups_file($c);
    $self->download_urls($c);
    $self->top_markers($c);
}

sub input_files {
    my ($self, $c) = @_;
    
    #$self->genotype_file($c);
    $self->phenotype_file($c);
  
    my $pheno_file  = $c->stash->{phenotype_file};
   #my $geno_file   = $c->stash->{genotype_file};
    my $traits_file = $c->stash->{selected_traits_file};
    my $trait_file  = $c->stash->{trait_file};
    my $pop_id      = $c->stash->{pop_id};
   
    my $input_files = join ("\t",
                            $pheno_file,
                            $traits_file,
                            $trait_file
        );

    my $tmp_dir         = $c->stash->{solgs_tempfiles_dir};
    my ($fh, $tempfile) = tempfile("input_files_${pop_id}-XXXXX", 
                                   DIR => $tmp_dir
        );

    $fh->print($input_files);
   
    $c->stash->{input_files} = $tempfile;
  
}

sub output_files {
    my ($self, $c) = @_;
    
    my $pop_id = $c->stash->{pop_id};
    my $trait  = $c->stash->{trait_abbr}; 
    
    $self->gebv_marker_file($c);  
    $self->gebv_kinship_file($c); 
    $self->validation_file($c);

    my $file_list = join ("\t",
                          $c->stash->{gebv_kinship_file},
                          $c->stash->{gebv_marker_file},
                          $c->stash->{validation_file},
                          $c->stash->{selected_traits_gebv_file}
        );
                          
    my $tmp_dir = $c->stash->{solgs_tempfiles_dir};

    my ($fh, $tempfile) = tempfile("output_files_${trait}_$pop_id-XXXXX", 
                                   DIR => $tmp_dir
        );

    $fh->print($file_list);
    
    $c->stash->{output_files} = $tempfile;

}

sub gebv_marker_file {
    my ($self, $c) = @_;
   
    my $pop_id = $c->stash->{pop_id};
    my $trait  = $c->stash->{trait_abbr};
    
    my $cache_data = {key       => 'gebv_marker_' . $pop_id . '_'.  $trait,
                      file      => 'gebv_marker_' . $trait . '_' . $pop_id,
                      stash_key => 'gebv_marker_file'
    };

    $self->cache_file($c, $cache_data);

}

sub gebv_kinship_file {
    my ($self, $c) = @_;

    my $pop_id = $c->stash->{pop_id};
    my $trait  = $c->stash->{trait_abbr};
 
    my $cache_data = {key       => 'gebv_kinship_' . $pop_id . '_'.  $trait,
                      file      => 'gebv_kinship_' . $trait . '_' . $pop_id,
                      stash_key => 'gebv_kinship_file'
    };

    $self->cache_file($c, $cache_data);

}

sub blups_file {
    my ($self, $c) = @_;
    
    $c->stash->{blups} = $c->stash->{gebv_kinship_file};
    $self->top_blups($c);
}

sub download_blups :Path('/download/blups/pop') Args(3) {
    my ($self, $c, $pop_id, $trait, $trait_id) = @_;   
 
    $self->get_trait_name($c, $trait_id);
    $c->stash->{pop_id} = $pop_id;

    $self->output_files($c);
    $self->blups_file($c);
    my $blups_file = $c->stash->{blups};

    unless (!-e $blups_file || -s $blups_file == 0) 
    {
        my @blups =  map { [ split(/\t/) ] }  read_file($blups_file);
    
        $c->stash->{'csv'}={ data => \@blups };
        $c->forward("solGS::View::Download::CSV");
    } 

}

sub download_marker_effects :Path('/download/marker/pop') Args(3) {
    my ($self, $c, $pop_id, $trait, $trait_id) = @_;   
 
    $self->get_trait_name($c, $trait_id);
    $c->stash->{pop_id} = $pop_id;

    $self->gebv_marker_file($c);
    my $markers_file = $c->stash->{gebv_marker_file};

    unless (!-e $markers_file || -s $markers_file == 0) 
    {
        my @effects =  map { [ split(/\t/) ] }  read_file($markers_file);
    
        $c->stash->{'csv'}={ data => \@effects };
        $c->forward("solGS::View::Download::CSV");
    } 

}

sub download_urls {
    my ($self, $c) = @_;
    
    my $pop_id         = $c->stash->{pop_id};
    my $trait_id       = $c->stash->{trait_id};
    my $blups_url      = qq | <a href="/download/blups/pop/$pop_id/trait/$trait_id">Download all GEBVs</a> |;
    my $marker_url     = qq | <a href="/download/marker/pop/$pop_id/trait/$trait_id">Download all marker effects</a> |;
    my $validation_url = qq | <a href="/download/validation/pop/$pop_id/trait/$trait_id">Download</a> |;
    
    $c->stash(blups_download_url          => $blups_url,
              marker_effects_download_url => $marker_url,
              validation_download_url     => $validation_url
        );
}

sub top_blups {
    my ($self, $c) = @_;
    
    my $blups_file = $c->stash->{blups};
    
    open my $fh, "<", $blups_file or die "couldnot open $blups_file: $!";
    
    my @top_blups;
    
    while (<$fh>)
    {
        push @top_blups,  map { [ split(/\t/) ] } $_;
        last if $. == 11;
    }

    shift(@top_blups); #add condition

    $c->stash->{top_blups} = \@top_blups;
}

sub top_markers {
    my ($self, $c) = @_;
    
    my $markers_file = $c->stash->{gebv_marker_file};

    open my $fh, $markers_file or die "couldnot open $markers_file: $!";
    
    my @top_markers;
    
    while (<$fh>)
    {
        push @top_markers,  map { [ split(/\t/) ] } $_;
        last if $. == 11;
    }

    shift(@top_markers); #add condition

    $c->stash->{top_marker_effects} = \@top_markers;
}

sub validation_file {
    my ($self, $c) = @_;

    my $pop_id = $c->stash->{pop_id};
    my $trait  = $c->stash->{trait_abbr};
    
    my $cache_data = {key       => 'cross_validation_' . $pop_id . '_' . $trait, 
                      file      => 'cross_validation_' . $trait . '_' . $pop_id,
                      stash_key => 'validation_file'
    };

    $self->cache_file($c, $cache_data);

}

sub combined_gebvs_file {
    my ($self, $c, $identifier) = @_;

    my $pop_id = $c->stash->{pop_id};
     
    my $cache_data = {key       => 'selected_traits_gebv_' . $pop_id . '_' . $identifier, 
                      file      => 'selected_traits_gebv_' . $pop_id . '_' . $identifier,
                      stash_key => 'selected_traits_gebv_file'
    };

    $self->cache_file($c, $cache_data);

}

sub download_validation :Path('/download/validation/pop') Args(3) {
    my ($self, $c, $pop_id, $trait, $trait_id) = @_;   
 
    $self->get_trait_name($c, $trait_id);
    $c->stash->{pop_id} = $pop_id;

    $self->validation_file($c);
    my $validation_file = $c->stash->{validation_file};

    unless (!-e $validation_file || -s $validation_file == 0) 
    {
        my @validation =  map { [ split(/\t/) ] }  read_file($validation_file);
    
        $c->stash->{'csv'}={ data => \@validation };
        $c->forward("solGS::View::Download::CSV");
    } 

}

sub model_accuracy {
    my ($self, $c) = @_;
    my $file = $c->stash->{validation_file};
    my @report =();

    if ( !-e $file) { @report = (["Validation file doesn't exist.", "None"]);}
    if ( -s $file == 0) { @report = (["There is no cross-validation output report.", "None"]);}
    
    if (!@report) 
    {
        @report =  map  { [ split(/\t/, $_) ]}  read_file($file);
    }

    shift(@report); #add condition

    $c->stash->{accuracy_report} = \@report;
   
}

sub get_trait_name {
    my ($self, $c, $trait_id) = @_;

    my $trait_name = $c->model('solGS')->trait_name($c, $trait_id);
  
    if (!$trait_name) 
    { 
        $c->throw(public_message =>"No trait name corresponding to the id was found in the database.", 
                  is_client_error => 1, 
            );
    }

    my $abbr = $self->abbreviate_term($trait_name);
    
    $c->stash->{trait_id}   = $trait_id;
    $c->stash->{trait_name} = $trait_name;
    $c->stash->{trait_abbr} = $abbr;
}

sub rank_genotypes : Path('/rank/genotypes/population') :Args(1) {
    my ($self, $c, $pop_id) = @_;
    
    $c->stash->{pop_id} = $pop_id;
    
}

sub traits_to_analyze : Path('/analyze/traits/population') :Args(1) {
    my ($self, $c, $pop_id) = @_;
    
    $c->stash->{pop_id} = $pop_id;
    my @selected_traits = $c->req->param('trait');
    
    if (!@selected_traits)
    {
        $c->stash->{no_traits_selected} = 'none';
        $c->stash->{referer} = $c->req->path;       
        $c->forward('population');
    }
    else 
    {
        my $traits;    
        for (my $i = 0; $i <= $#selected_traits; $i++)
        {
            $traits .= $selected_traits[$i];
            $traits .= "\t" unless ($i == $#selected_traits);           
        } 
        
        my $trait_id;
        foreach (@selected_traits)
        {
            $trait_id .= $c->model('solGS')->get_trait_id($c, $_);
        } 
        
        my $identifier = crc($trait_id);

        $self->combined_gebvs_file($c, $identifier);
        
        my $tmp_dir     = $c->stash->{solgs_tempfiles_dir}; 
        my ($fh, $file) = tempfile("selected_traits_pop_${pop_id}-XXXXX", 
                               DIR => $tmp_dir
            );

        $fh->print($traits);
        $fh->close;

        my ($fh2, $file2) = tempfile("trait_${trait_id}_pop_${pop_id}-XXXXX", 
                                     DIR => $tmp_dir
            );
        $fh2->close;
  
        $c->stash->{selected_traits_file} = $file;
        $c->stash->{trait_file} = $file2;
        $c->forward('get_rrblup_output');
    }
}

sub get_all_traits {
    my ($self, $c) = @_;
    
    my $pheno_file = $c->stash->{phenotype_file};
    
    open my $ph, "<", $pheno_file or die "$pheno_file:$!\n";
    my $headers = <$ph>;
    $headers =~ s/uniquename\t|stock_id\t|stock_name\t//g;
    $ph->close;

    $self->add_trait_ids($c, $headers);
       
}

sub add_trait_ids {
    my ($self, $c, $list) = @_;   
    $list =~ s/\n//;
    my @traits = split (/\t/, $list);

    my $table = 'trait_name' . "\t" . 'trait_id' . "\n"; 
    
    foreach (@traits)
    {
        my $trait_id = $c->model('solGS')->get_trait_id($c, $_);
        $table .= $_ . "\t" . $trait_id . "\n";
    }

    $self->all_traits_file($c);
    my $traits_file =  $c->stash->{all_traits_file};
    
    write_file($traits_file, $table);

}

sub all_traits_file {
    my ($self, $c) = @_;

    my $pop_id = $c->stash->{pop_id};

    my $cache_data = {key       => 'all_traits_pop' . $pop_id,
                      file      => 'all_traits_pop_' . $pop_id,
                      stash_key => 'all_traits_file'
    };

    $self->cache_file($c, $cache_data);

}

sub analyzed_traits {
    my ($self, $c) = @_;
    my $pop_id = $c->stash->{pop_id};

    my $dir = $c->stash->{solgs_cache_dir};
    opendir my $dh, $dir or die "can't open $dir: $!\n";
    
    my @files  = map { $_ =~ /($pop_id)/ ? $_ : 0 } 
                 grep { /gebv_kinship_[a-zA-Z0-9]/ && -f "$dir/$_" } 
                 readdir($dh);   
    closedir $dh;
    
    my @traits = map { s/gebv|kinship|_|($pop_id)//g ? $_ : 0} @files;
  
    $c->stash->{analyzed_traits} = \@traits;
    $c->stash->{analyzed_traits_files} = \@files;
}

sub abbreviate_term {
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

sub phenotype_file {
    my ($self, $c) = @_;
    my $pop_id     = $c->stash->{pop_id};
    
    die "Population id must be provided to get the phenotype data set." if !$pop_id;
  
    my $file_cache  = Cache::File->new(cache_root => $c->stash->{solgs_cache_dir});
    $file_cache->purge();
   
    my $key        = "phenotype_data_" . $pop_id;
    my $pheno_file = $file_cache->get($key);

    unless ($pheno_file)
    {  
        $pheno_file = catfile($c->stash->{solgs_cache_dir}, "phenotype_data_" . $pop_id . ".txt");
        $c->model('solGS')->phenotype_data($c, $pop_id);
        my $data = $c->stash->{phenotype_data};
  
        $data = $self->format_phenotype_dataset($data);
        write_file($pheno_file, $data);

        $file_cache->set($key, $pheno_file, '30 days');
    }
   
    $c->stash->{phenotype_file} = $pheno_file;

}

sub format_phenotype_dataset {
    my ($self, $data) = @_;
    
    my @rows = split (/\n/, $data);
    
    $rows[0] =~ s/SP:\d+\|//g;  
    $rows[0] =~ s/\w+:\w+\|//g;
  
    my @headers = split(/\t/, $rows[0]);
    
    my $header;
    my $cnt = 0;
    
    foreach (@headers)
    {
        $cnt++;
        $header .= $self->abbreviate_term($_);    
        unless ($cnt == scalar(@headers))
        {
            $header .= "\t";
        }
    }
    
    $rows[0] = $header;
    
    foreach (@rows)
    {
        $_ =~ s/\s+plot//g;
        $_ .= "\n";
    }

    return \@rows;
}

sub genotype_file :Private {
    my ($self, $c) = @_;

    my $pop_id = $c->stash->{pop_id};
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

sub get_rrblup_output :Private{
    my ($self, $c) = @_;
    
    my $pop_id = $c->stash->{pop_id};
    my $trait  = $c->stash->{trait_abbr};
   
    my ($traits_file, @traits, @trait_pages);
   
    if ($trait)     
    {
        $self->run_rrblup_trait($c, $trait);  
    }
    else 
    {    
        $traits_file = $c->stash->{selected_traits_file};
        my $content  = read_file($traits_file);
     
        if ($content =~ /\t/)
        {
            @traits = split(/\t/, $content);
        }
        else
        {
            push  @traits, $content;
        }
            
       foreach (@traits) 
       {                       
           $self->run_rrblup_trait($c, $_);
           my $trait_id = $c->stash->{trait_id};
           push @trait_pages, [ qq | <a href="/trait/$trait_id/population/$pop_id">$_</a>| ];
       }    
    }

    if (scalar(@traits) == 1) 
    {
        $self->gs_files($c);
        $c->stash->{template} = 'population/trait.mas';
    }
    
    if (scalar(@traits) > 1)    
    {
        $self->analyzed_traits($c);
        $c->stash->{template}    = '/population/multiple_traits_output.mas'; 
        $c->stash->{trait_pages} = \@trait_pages;
    }

}
sub run_rrblup_trait {
    my ($self, $c, $trait) = @_;
    my $pop_id = $c->stash->{pop_id};

    my $trait_id = $c->model('solGS')->get_trait_id($c, $trait);
    $c->stash->{trait_id}   = $trait_id ; 
    $c->stash->{trait_abbr} = $trait;                          
        
    my ($fh, $file) = tempfile("trait_${trait_id}_pop_${pop_id}-XXXXX", 
                               DIR => $c->stash->{solgs_tempfiles_dir}
        );
        
    $fh->close;   

    $c->stash->{trait_file} = $file;       
    write_file($file, $trait);

    $self->output_files($c);
    if (-s $c->stash->{gebv_kinship_file} == 0 ||
        -s $c->stash->{gebv_marker_file}  == 0 ||
        -s $c->stash->{validation_file}   == 0
        )
    {  
        $self->input_files($c);            
        $self->output_files($c);  
        $self->run_rrblup($c);    
    }
}

sub run_rrblup  {
    my ($self, $c) = @_;
   
    #get all input files & arguments for rrblup, 
    #run rrblup and save output in solgs user dir
    my $pop_id       = $c->stash->{pop_id};
    my $trait_id     = $c->stash->{trait_id};
    my $input_files  = $c->stash->{input_files};
    my $output_files = $c->stash->{output_files};
    
    die "\nCan't run rrblup without a trait id." if !$trait_id;
    die "\nCan't run rrblup without a population id." if !$pop_id;
    die "\nCan't run rrblup without input files." if !$input_files;
    die "\nCan't run rrblup without output files." if !$output_files;    
    
    $c->stash->{r_temp_file} = "gs-rrblup-${trait_id}-${pop_id}";
    $c->stash->{r_script}    = 'R/gs.r';
    $self->run_r_script($c);
}

sub run_r_script {
    my ($self, $c) = @_;
    
    my $r_script     = $c->stash->{r_script};
    my $input_files  = $c->stash->{input_files};
    my $output_files = $c->stash->{output_files};
    my $r_temp_file  = $c->stash->{r_temp_file};
  
    CXGN::Tools::Run->temp_base($c->stash->{solgs_tempfiles_dir});
    my ( $r_in_temp, $r_out_temp ) =
        map 
    {
        my ( undef, $filename ) =
            tempfile(
                catfile(
                    CXGN::Tools::Run->temp_base(),
                    "${r_temp_file}-$_-XXXXXX",
                ),
            );
        $filename
    } 
    qw / in out /;
    {
        my $r_cmd_file = $c->path_to($r_script);
        copy($r_cmd_file, $r_in_temp)
            or die "could not copy '$r_cmd_file' to '$r_in_temp'";
    }

    try 
    {
        my $r_process = CXGN::Tools::Run->run_cluster(
            'R', 'CMD', 'BATCH',
            '--slave',
            "--args $input_files $output_files",
            $r_in_temp,
            $r_out_temp,
            {
                working_dir => $c->stash->{solgs_tempfiles_dir},
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
        
        $c->throw($err);
    };


}

  
sub get_solgs_dirs {
    my ($self, $c) = @_;
   
    my $solgs_dir       = $c->config->{solgs_dir};
    my $solgs_cache     = catdir($solgs_dir, 'cache'); 
    my $solgs_tempfiles = catdir($solgs_dir, 'tempfiles');
  
    mkpath ([$solgs_dir, $solgs_cache, $solgs_tempfiles], 0, 0755);
   
    $c->stash(solgs_dir           => $solgs_dir, 
              solgs_cache_dir     => $solgs_cache, 
              solgs_tempfiles_dir => $solgs_tempfiles
        );

}

sub cache_file {
    my ($self, $c, $cache_data) = @_;
    
    my $solgs_cache = $c->stash->{solgs_cache_dir};
    my $file_cache  = Cache::File->new(cache_root => $solgs_cache);
    $file_cache->purge();

    my $file  = $file_cache->get($cache_data->{key});

    unless ($file)
    {      
        $file = catfile($solgs_cache, $cache_data->{file});
        write_file($file);
        $file_cache->set($cache_data->{key}, $file, '30 days');
    }

    $c->stash->{$cache_data->{stash_key}} = $file;
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
