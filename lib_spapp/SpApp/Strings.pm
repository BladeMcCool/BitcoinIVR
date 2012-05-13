package SpApp::Strings;

use strict;

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;

	my $web_app = shift; #needed for access to dbh, query, session, etc.
	my $other_args = shift;

	$self->{_ERROR_COND} = undef;	#set up for error method. why here? dunno.
	if (!$web_app) {
		$self->error('new needs a webapp.');
	}
	$self->{wa} = $web_app;
	
	return $self;
}

sub error {
	my $self = shift;
	my $value = shift;
	
	if ($value) {
		$self->{_ERROR_COND} = $value;
	} else {
		return $self->{_ERROR_COND};
	}
}

sub get_strings {
	my $self = shift;
	my $stringnames = shift; #should be arrayref of string names.
	my $args = shift; #should at least specify the language requested for the strings.
	
	my $lang = $args->{lang};
	if (!$lang) { $lang = 'en'; } #reasonable default since this is the language _I_ speak and _I_ am writing the code.
	
	if (ref($stringnames) ne 'ARRAY') {
		$stringnames = [ $stringnames ]; #silently make into arrayref if needed.
	}
	my $text_fld = 'text_' . $lang;
	
	my $string_sql = "SELECT $text_fld AS text, render_with_htc FROM app_interface_string WHERE stringname = ?";
	$self->{wa}->ch_debug(['get_strings: with sql like ', $string_sql, 'for strings named:', $stringnames]);
	my $dbh = $self->{wa}->get_dbh();
	my $sth = $dbh->prepare($string_sql) or die $dbh->errstr;

	my $strings = {};
	my $debug = 0; #some different ways to turn this on - when on should embed the lang and stringname within the string.
	if ($self->{wa}->param('debug_mode') || $self->{wa}->config('include_strings_debug')) {	
		$debug = 1;
	}
	my $render_all_with_htc = $args->{render};
	foreach (@$stringnames) {
		$self->{wa}->ch_debug(['get_strings: for a string named: ', $_]);
		if (!$_) { next; } #skip undef (or close to undef) string names.
		$sth->execute($_) or die $dbh->errstr;
		my $row = $sth->fetchrow_hashref();
		
		#what to call it? 
			#leave unchanged for now.
		#my $stringname = 'istr_' . $_; #Debating whether to prefix these or not. Doing so will make it clear what the vars are, but will add a lot of "istr_" . $foo all over the place which would be stupidly annoying.
		my $stringname = $_; 
		
		$strings->{$stringname} = $row->{text};
		if ($debug) {
			$strings->{$stringname} = "($lang $stringname) " . $strings->{$stringname};
		}
		$self->{wa}->ch_debug(['get_strings: got a row like: ', $row]);

		#any processing? Variables to plug in to <%foo%> things in the strings? We'd need an arg called "substitutions" which would be a hashref of placeholders => values to substitute.
			#note that means that substitution variable names are be globally unique. the same substitution will be made in all strings that contain such a placeholder.
			#Question... why am I rolling my own here? Why not treat the string as a template? ok ok .. I think I _will_ add that when I actually want to do stuff ... can levae this roll-my-own version too .. would depend on what was asked for .. if we got a tmpl_params we could maybe do it ... 
		if ($args->{substitutions} && ref($args->{substitutions}) eq 'HASH') {
			$strings->{$stringname} =~ s|<%(.*?)%>|$args->{substitutions}->{$1}|ge;
		}
		
		#or plug shit in a different way? (treat like a tmpl and plug in tmpl_params)
		my $render_with_htc = $render_all_with_htc; #could be 0 or 1
		if ($row->{render_with_htc}) { $render_with_htc = 1; } #but this could turn it to 1 for this string, regardless of the function-call arg 
		if ($render_with_htc) {
			my $tmpl_params = $self->{wa}->get_common_tmpl_vars();
			if ($args->{tmpl_params} && ref($args->{tmpl_params}) eq 'HASH') { 
				$tmpl_params = { %{$args->{tmpl_params}}, %$tmpl_params }; #merge!
			}
			#$self->ch_debug(['rendering string name with params:', $stringname, ]);
			#$strings->{$stringname} = something like load tmpl from scalar, pass params, and render output.
			
			my $t = HTML::Template::Compiled->new(
				scalarref               => \$strings->{$stringname},
				cache                   => 0,
				global_vars             => 2, #with HTC this being 2 should allow the ... notation for going up one level. which I want to be able to do inside loops. to access main tmpl vars. --- of course I couldnt get that to work reliably. after clearing the cache I got it to work for the first iteration of the loop then it fails .. very queer. docs say global_vars = 1 is best for speed so gonna try that and that should fix the issue anyways. Yeah that didnt work either. something aint right. a small proof of concept program worked properly. i dont know what is the deal. Update: there was a bug in HTC. Fixed in version 0.67. I helped point it out and demonstrate it to Tina (HTC maintainer). w00t. 
				loop_context_vars	      => 1, #with this as 1, includes with HTC dont seem to be using it, so shit isnt working. going to use the <TMPL_LOOP_CONTEXT> HTC feature instead, and only when needed. that'll save CPU in any case, according to the docs.
				path			              => [ $self->{wa}->param('_tmpl_path'), ],
				search_path_on_include	=> 1,
				max_includes 		        => 10000
			);
			$t->param($tmpl_params);
			$strings->{$stringname} = $t->output();
		}
	}
	#$self->{wa}->ch_debug(['get_strings: sending back strings like: ', $strings]);
	
	return $strings;
}


1;
