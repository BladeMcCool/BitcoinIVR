#The following is ripped and hacked from CGI::Application::Plugin::Apache and CGI::Application::Plugin::Apache::Request.
#I just wanted a subset, and wanted to hack it up a bit to forget about the existence of MP1 since there is no reason any new server should be set up on MP1 anymore and the application is being developed solely with mp2 in mind.
#Much thanks to the original author(s) of the CPAN module, Michael Peters, and the rest of the CGIApp crew (whom I dont know personally, but am well aware of the contribution these guys have put forth) as well as all the other contributors to this code which seems to be many sourced. I see Randal Schwartz named in comments. I also know some of it comes from CGI.pm.

#With this module I again want to ditch mp1 thoughts, and lose some shit.

package SpApp::CAPARRipAPReq;
use strict;
use base 'Apache2::Request';
#use Apache2::Cookie;
#use Apache2::URI;
#use Apache2::Upload;
#use HTML::GenerateUtil;

sub new {
		my($class, @args) = @_;
		return bless $class->SUPER::new(@args), $class;
}

sub param {
    my ($self, @args) = @_;
    # if we just want the value of a param
    if( scalar @args <= 1) {
        return $self->SUPER::param(@args);
    # else we want to set the value of the param
    } else {
        return $self->args->{$args[0]} = $args[1];
    }
}

sub delete {
    my ($self, @args) = @_;
    my $table = $self->parms();
    foreach my $arg (@args) {
        delete $table->{$arg};
    }
}

sub delete_all {
    my $self = shift;
    my $table = $self->parms();
    my @args = keys %$table;
    foreach my $arg (@args) {
        delete $table->{$arg};
    }
}

sub cookie {
    my ($self, @args) = @_;
    if($#args == 0) {
        # if we just have a name of a cookie then retrieve the value of the cookie
        my $cookies = Apache2::Cookie->fetch($self);
        if( $cookies && $cookies->{$args[0]} ) {
            return $cookies->{$args[0]}->value;
        } else {
            return;
        }
    } else {
        # else we have several values (all the properties of a cookie to set) so try and create a new cookie
        return Apache2::Cookie->new($self, @args);
    }
}

sub Dump {
    my $self = shift;
    my($param,$value,@result);
    return '<ul></ul>' unless $self->param;
    push(@result,"<ul>");
    foreach $param ($self->param) {
        my $name = $self->escapeHTML($param);
        push(@result,"<li><strong>$name</strong></li>");
        push(@result,"<ul>");
        foreach $value ($self->param($param)) {
            $value = $self->escapeHTML($value);
            push(@result,"<li>$value</li>");
        }
        push(@result,"</ul>");
    }
    push(@result,"</ul>");
    return join("\n",@result);
}

sub Vars {
    my $self = shift;
    my @params = $self->param();
    my %Vars = ();
    foreach my $param (@params) {
        my @values = $self->param($param);
        if( scalar @values == 1 ) {
            $Vars{$param} = $values[0];
        } else {
            $Vars{$param} = \@values;
        }
    }

    if(wantarray) {
        return %Vars;
    } else {
        return \%Vars;
    }
}

sub escapeHTML {
    my ($self, $value) = @_;
    $value = HTML::GenerateUtil::escape_html($value, 
        (
            $HTML::GenerateUtil::EH_LFTOBR 
            | $HTML::GenerateUtil::EH_SPTONBSP 
            | $HTML::GenerateUtil::EH_LEAVEKNOWN
        )
    ); 
    return $value;
}

sub unescape {
	my $self = shift;
	my $url = shift;
	return Apache2::URI::unescape_url($url);
}

sub upload {
    my ($self, $file) = @_;
    #die "you are trying the upload function from the CAPARRip. module. uncomment this line and see if it works better than the vanilla one. - this function is probably here for a upload plugin that I should be using!";
    # if they want a specific one, then lets give them the file handle
    if( $file ) {
        my $upload = $self->SUPER::upload($file);
        if( $upload ) {
            return $upload->fh();
        } else {
            return;
        }
    # else they want them all
    } else {
        my @files = $self->SUPER::upload();
        @files = map { $self->SUPER::upload($_)->fh() } @files;
        return @files;
    }
}

1;
