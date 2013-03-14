#!/usr/bin/env perl

# run the test script something like this:
#CATALYST_DEBUG=0 CATALYST_SERVER=http://virtual:3000/ prove -v solgs_app.t 

use strict;
use warnings;
use Test::More;
use Test::WWW::Mechanize::Catalyst 'solGS';

BEGIN { use_ok( 'Test::WWW::Mechanize::Catalyst' ) or 
            BAIL_OUT('Could not load Test::WWW::Mechanize::Catalyst');
}

BEGIN { use_ok( 'Test::More' ) or 
            BAIL_OUT('Could not load Test::More');
}

BEGIN { use_ok(  'solGS::Controller::Root'  ) or
        BAIL_OUT( 'Could not load solGS::Controller::Root');   
}
BEGIN { use_ok(  'solGS::Model::solGS'  ) or
        BAIL_OUT( 'Could not load solGS::Model::solGS');   
}
BEGIN { use_ok(  'solGS::Controller::Stock'  ) or
        BAIL_OUT( 'Could not load solGS::Controller::Stock');   
}   

#my $solgs_server_name = $ENV{SOLGS_TEST_SERVER};

my $mech = Test::WWW::Mechanize::Catalyst->new;
#$mech->{catalyst_debug} = 0;
#$mech->{catalyst_info} = 0;
#$mech->get_ok($solgs_server_name, 'homepage loaded');
$mech->get_ok('/', 'homepage loaded');
$mech->get_ok('/search', 'search page');
$mech->content_contains('Search for a trait', 'search trait section');
$mech->content_contains('Browse by traits', 'traits index');

my @traits_indices = $mech->find_all_links( url_regex => qr/gs\/traits/i );
$mech->links_ok( \@traits_indices, 'trait indices links work' );
$mech->get_ok($traits_indices[0], 'a page for a list of traits starting with a certain letter');
$mech->content_contains('Traits beginning with', 'traits list section');

my @traits_list= $mech->find_all_links( url_regex => qr/search\/result\/traits/i );
$mech->links_ok( \@traits_list, 'links to traits starting with a certain letter work.' );
$mech->get_ok($traits_list[0], 'a link to a traits search page works');
$mech->content_contains('Traits with genomic selection data',  'Traits with genomic selection data');

my @traits_pop= $mech->find_all_links( url_regex => qr/search\/result\/populations/i );
$mech->links_ok( \@traits_pop, 'links to search page for populations evaluated for a trait work.' );
$mech->get_ok($traits_pop[0], 'a link to populations evaluated for a trait  search page works');
$mech->get_ok($traits_pop[0], $traits_pop[0]->url);
$mech->content_contains('GS training populations', 'training populations section');

# diag('Please wait..this may take a few minutes..');
# my @training_pops = $mech->find_all_links(url_regex=> qr/trait\/70682\/population/);


# foreach my $tr_pop (@training_pops) {
#     my $url = $tr_pop->url;
#     $mech->links_ok( $url, $url ) or 
#         diag("if similar urls are passing the test, page $url  might be 
#               failing because of the type of its dataset.");
# }

$mech->get_ok('/trait/70682/population/128', 'a training population page');
$mech->content_contains($_)
      for (
        'Population summary',
        'Trait phenotype data',
        'Predicted genomc estimated breeding values', 
        'Top 10 genotypes',
        'Marker Effects',
        '10 folds cross-validation report',
      );

diag('GEBV data download');
my $gebv_download_link = $mech->find_link( text_regex => qr/download all gebvs/i );
ok( $gebv_download_link, 'got a GEBV data download link' );
my $url = defined $gebv_download_link ? $gebv_download_link->url : '';
$url ? $mech->links_ok( $url, 'GEBV data download link works' ) 
    : ok(0, 'no GEBV download url found');
$mech->get_ok($url);
my $size =  length( $mech->content );
cmp_ok( $size, '>=', 1000,"got at least 1KB (file size: $size, $url) of data from the GEBV data download url" );


diag('Marker Effects data download');
$mech->get_ok('/trait/70682/population/128', 'a training population page');
my $marker_download_link = $mech->find_link( text_regex => qr/download all marker effects/i );
ok( $marker_download_link, 'got a marker effects data download link' );
$url = defined $marker_download_link ? $marker_download_link->url : '';
$url ? $mech->links_ok( $url, 'Marker effects data download link works' ) 
    : ok(0, 'no marker effects download url found');
$mech->get_ok($url);
$size =  length( $mech->content );
cmp_ok( length( $mech->content ), '>=', 1000,"got at least 1KB (file size: $size, $url) of data from the marker effects data download url" );


diag('Model accuracy data download');
$mech->get_ok('/trait/70682/population/128', 'a training population page');
my $accuracy_download_link = $mech->find_link( text_regex => qr/download model accuracy/i );
ok( $accuracy_download_link, 'got a model accuracy data download link' );
$url = defined $accuracy_download_link ? $accuracy_download_link->url : '';
$url ? $mech->links_ok( $url, 'Model accuracy data download link works' ) 
    : ok(0, 'no model accuracy download url found');
$mech->get_ok($url);
$size =  length( $mech->content);
cmp_ok( $size, '>=', 100,"got at least 0.1KB (file size: $size, $url) of data from the model accuracy data download url" );


$mech->get_ok('/population/128', 'Got a population page');
$mech->content_contains($_)
      for (
        'Population summary',
        'Traits',
        'Run GS',
      );

diag("Please wait... this may a few minutes..");
my @traits= $mech->find_all_links( url_regex => qr/trait/ );
my $no_traits = scalar(@traits);
cmp_ok($no_traits, '>=', 1, "this population has $no_traits traits for GS analysis");

diag("Please wait... this may take a few minutes..");
$url = $traits[0]->url;
$mech->get_ok($traits[0], "run GS for a trait ($url) of a training population");
$mech->content_contains($_)
      for (
        'Population summary',
        'Trait phenotype data',
        'Predicted genomc estimated breeding values', 
        'Top 10 genotypes',
        'Marker Effects',
        '10 folds cross-validation report',
      );



done_testing();
