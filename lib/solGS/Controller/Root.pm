package solGS::Controller::Root;
use Moose;
use namespace::autoclean;


use Scalar::Util 'weaken';
use CatalystX::GlobalContext ();

use CXGN::Login;
use CXGN::People::Person;

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

sub search : Path('/search/solgs') Args(0) FormConfig('search/solgs.yml') {
    my ($self, $c) = @_;
    my $form = $c->stash->{form};

    if ($form->submitted_and_valid) 
    {
        my $query = $form->param_value('search.search_term');
        $c->res->redirect("/search/results/$query");
    }        
    else
    {
        $c->stash(template => '/search/solgs.mas',
                  form     => $form
            );
    }

}

sub show_search_result : Path('/search/results') Args(1) {
    my ($self, $c, $query) = @_;
  
    #do search and display results
    my $result = [ [qq|<a href="/population/12">pop1</a>|, 'loc', 2012, 'ER'] ];
    my $form;

    if ($result)
    {
       $c->stash(template => '/search/result.mas',
                 result   => $result,
                 form     => $form
           );
    }
    else
    {
        $c->res->redirect('/search/solgs');
    }

}  
sub population :Path('/population') Args(1) {
    my ($self, $c, $pop_id) = @_;
    $c->stash(template => '/population.mas',
              pop_id   => $pop_id
        );
}

sub default :Path {
    my ( $self, $c ) = @_;   
    $c->response->status(404);
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
