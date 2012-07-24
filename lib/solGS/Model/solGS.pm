package solGS::Model::solGS;

use Moose;
use namespace::autoclean;
use Bio::Chado::Schema;
use Bio::Chado::NaturalDiversity::Reports;
use File::Path qw / mkpath /;
use File::Spec::Functions;
use List::MoreUtils qw / uniq /;

extends 'Catalyst::Model';

=head1 NAME

solGS::Model::solGS - Catalyst Model for solGS

=head1 DESCRIPTION

solGS Catalyst Model.

=head1 AUTHOR

Isaak Y Tecle, iyt2@cornell.edu

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut



sub solgs_phenotype_data {
    my ($self, $pop_id) = @_;
    return $self->get_file('phenotype', $pop_id);
}

sub solgs_genotype_data {
    my ($self, $pop_id) = @_;
   return $self->get_file('genotype', $pop_id);
}


sub get_file {
    my ($self, $c, $type, $pop_id) = @_; 
    my $solgs_path = $self->solgs_path($c);
    my $trait = 'abc'; # figure out how to determine trait data file...
    
    if ($type eq 'phenotype')
    {
        return  catfile($solgs_path, $pop_id, $type, $trait);
    }
    else
    {
    return  catfile($solgs_path, $pop_id, $type);
    }
}


sub file_paths {
    my ($self, $c, $pop_id) = @_; 
    my $solgs_path = catfile($self->solgs_path($c), $pop_id);
    my $geno_path  = catfile($solgs_path, 'genotype');
    my $pheno_path = catfile($solgs_path, 'phenotype');
  
    mkpath ([$geno_path, $pheno_path], 0, 0755);        
    return  $geno_path, $pheno_path;
   
}

sub solgs_path {
    my ($self, $c) = @_;
    return  $c->config->{'solgs'};
}


sub write_data {
#make query to db and store population level phenotype and genotype data in tab delimited files

}
sub data_quality {
#data quality, formatting check

}

sub search_trait {
    my ($self, $c, $trait) = @_;
    
    my $rs;
    if ($trait)
    {       
        $rs = $self->schema($c)->resultset("Phenotype::Phenotype")
            ->search({})
            ->search_related('observable', 
                             {
                                 'observable.name' => {'iLIKE' => '%' . $trait . '%'}
                             },
                             {
                                 columns => [ qw/ cvterm_id name definition / ] 
                             },    
                             { 
                                 distinct => 1,
                                 page     => $c->req->param('page') || 1,
                                 rows     => 10,
                                 order_by => 'name'              
                             },                                                        
            );             
    }

    return $rs;      
}

sub search_populations {
    my ($self, $c, $trait_id) = @_;
    
    my $rs = $self->schema($c)->resultset("Phenotype::Phenotype")
        ->search({'observable_id' =>  $trait_id})
        ->search_related('nd_experiment_phenotypes')
        ->search_related('nd_experiment')
        ->search_related('nd_experiment_stocks')
        ->search_related('stock')
        ->search_related('stock_relationship_subjects')
        ->search_related('object')
        ->search_related('stock_relationship_subjects');

    my @stock_ids;    
    while (my $row = $rs->next)
    {                    
        push @stock_ids, $row->object_id;
    }

    @stock_ids = uniq @stock_ids;

    my @pop_ids;
    foreach my $st (@stock_ids)
    {
        push @pop_ids, $st  if ($self->check_stock_type($c, $st) eq 'population');
    }

    return \@pop_ids;

}

sub get_population_details {
    my ($self, $c, $pop_id) = @_;
   
    return $self->schema($c)->resultset("Stock::Stock")
        ->search(
        {
            'stock_id' => $pop_id
        }, 
        );
}

sub trait_name {
    my ($self, $c, $trait_id) = @_;

    my $trait_name = $self->schema($c)->resultset('Cv::Cvterm')
        ->search( {cvterm_id => $trait_id})
        ->single
        ->name;

    return $trait_name;

}

sub check_stock_type {
    my ($self, $c, $stock_id) = @_;

    my $type_id = $self->schema($c)->resultset("Stock::Stock")
        ->search({'stock_id' => $stock_id})
        ->single
        ->type_id;

    return $self->schema($c)->resultset('Cv::Cvterm')
        ->search({cvterm_id => $type_id})
        ->single
        ->name;
}

sub phenotype_data {
     my ($self, $c, $pop_id ) = @_; 
    
     if ($pop_id) 
     {
         my $results  = [];                                    
         my $stock_rs = $self->schema($c)->resultset("Stock::Stock")->search( { stock_id => $pop_id } );
         $results     = $self->schema($c)->resultset("Stock::Stock")->recursive_phenotypes_rs($stock_rs, $results);
         my $report   = Bio::Chado::NaturalDiversity::Reports->new;
         my $data     = $report->phenotypes_by_trait($results);
      
         $c->stash->{phenotype_data} = $data;               
    }
}

sub schema {
    my ($self, $c) = @_;
    return  $c->dbic_schema("Bio::Chado::Schema");
} 

__PACKAGE__->meta->make_immutable;

#####
1;
#####
