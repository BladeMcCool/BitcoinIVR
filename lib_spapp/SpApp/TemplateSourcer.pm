package SpApp::TemplateSourcer;
use strict;
use Encode;

use vars qw {$_CONTENT_CACHE $_CONTENT_SLICE_CACHE}; #gonna try to cache to reduce the amount of file system and regex matching that has to get run. This may end up a) not working right or b) just be a bad idea for memory usage or some other mod_perly reason.
$_CONTENT_CACHE = {}; #
$_CONTENT_SLICE_CACHE = {};

sub new {
	my $invocant = shift;
	my $class    = ref($invocant) || $invocant;  # Object or class name
	my $self = {};
	bless $self, $class;

	my $webapp = shift; #or equivalent.
	my $other_args = shift; #should be a ref to the DataObj::new constructor $other_args

	if (!$webapp) {
		$self->error('new needs a webapp or equivalent.');
	}
	$self->{wa} = $webapp;

	return $self;
}

sub error {
	my $self = shift;
	print STDERR "error inside TemplateSourcer - will die on next line hoping to tell you about the error(s)";
	die "@_";
#	return $self->{'do'}->error(@_);
}

sub ch_debug {
	my $self = shift;
	return $self->{wa}->ch_debug(@_);
}

#get the html source of a file, and replace content between begin and end tokens with a tmpl_include for a template that has the <form> and <tmpl_var sub_tmpl> tags inside.
	#call it like { r => $r } from a hanlderutil to slurp the contents of the filename referenced by the request $r
	#call it like { source_file => '/full/system/path/to/file.html' } from a webapp (or even a handlerutil) to slurp the contents of the named file
sub source_template {
	my $self = shift;
	my $args = shift;
	
	$self->ch_debug(['source_template: with args like:', $args]);
	#die "see stacktrace - missing args?";
	
	my $html = undef;
	my $fatal_not_found = 1;
	if ($args->{soft_not_found}) {
		$fatal_not_found = 0
	}
	$self->{wa}->debuglog(['source_template with args like: ', $args, 'and fatal_not_found of', $fatal_not_found ]);
		
	if ($args->{r}) {
		if (!-e $args->{r}->filename()) { 
			if ($fatal_not_found) {
				$self->error("source_template: cannot source from file " . $args->{r}->filename() . "; file does not exist.");
			} else {
				return undef; #non-fatal version just returns undef at this time. caller should trap for undef response and handle accordingly.
			}
		} 

		$self->{wa}->debuglog(['source_tmplate: slurping file via $r']);
		$html = ${ $args->{r}->slurp_filename() }; #defereence the result since we gonna process it.

		#if we _got_ r, then we can just assume that we're to USE r to slurp_filename in order to get it. I suppose one day that might not be the case, but lets go with it for now.
	} elsif ($args->{source_file})  {
		#real work to check the file exists, etc. and then slurp it in.
		if (!-e $args->{source_file}) { 
			if ($fatal_not_found) {
				$self->error("source_template: cannot source from file $args->{source_file}; file does not exist.");	
			} else {
				return undef; #non-fatal version just returns undef at this time. caller should trap for undef response and handle accordingly.
			}
		} 
		$self->ch_debug(['source_tmplate: reading file from filesystem ourselves']);
		
		#open INFILE, "<$args->{source_file}";
		open INFILE, "<:utf8", $args->{source_file};
		while (<INFILE>) {
			$html .= $_;
		}
		close INFILE;
	}
	#$html = decode_utf8($html);
	#$html = decode("utf8", $html); #I thought this and the line above were the same thing? well they get a different result -- this one gives me an error of sorts where the one above just silently fucks itself and ends up with no output at all.
	
	#debug for that utf issue (I think reading stuff as utf8 and flushing the cache fixed it)
	#use Digest::MD5;
	#Encode::_utf8_off($html); #dangerous/bad.
	#my $md5 = Digest::MD5::md5_base64($html);
	#use Module::Info;
  #my $htc_i = Module::Info->new_from_module('HTML::Template::Compiled');
  #my $htcu_i = Module::Info->new_from_module('HTML::Template::Compiled::Utils');
	#$self->ch_debug(['source_template: htc path: ', $htc_i->inc_dir, 'htc utils path:', $htcu_i->inc_dir, 'htc version:', $htc_i->version, 'utf flag on the html var?', Encode::is_utf8($html) ]);
	$self->ch_debug(['source_template: utf flag on the html var?', Encode::is_utf8($html) ]);

	my $html_ref = \$html;
	$self->ch_debug(['source_template: obtained html and will next do preprocess subs on it']);
	
	#i want a system for preprocessing. basically a chain of arbitrary functions to run on the scalar ref of html. each one we'll get a 'sub' and 'args'.
	foreach (@{$args->{preprocess_subs}}) {
		#$self->ch_debug(['preprocess_subs loop with item like:', $_]);
		$html_ref = $_->{'sub'}->($self->{wa}, $html_ref, $_->{'args'}); #execute it. they must always accept a webapp and html_ref and should accept hashref of optional args. shoudl always send back the html_ref. (or possibly a ref to new html!?)
	}

	my $html = $$html_ref;

	#default to process them, but have ability not to.
	my $source_file_processing = 1;
	if (exists($args->{source_file_processing}) && !$args->{source_file_processing}) {
		$source_file_processing = 0;
	}
	
	if ($source_file_processing) {
		#another thing we assume is that this thing needs to have the main_form and <TMPL_VAR sub_tmpl> stuff crammed into it. We'll also assume that to do that we need to be able to load a template to do that. We'll assume that the template is a general template called "general/template_sourcer_master.tmpl". If that is ever different then we should just find a way to pass in arg to override.
		my $enclosure_tmpl = "general/template_sourcer_master.tmpl"; #this file is assumed to include at least the <form id="main_form" ><input type='hidden' name='rm' value='' /><TMPL_VAR sub_tmpl></form> stuff. see an actual template for complete thing 
	
		my $begin_token = '<!--start_printable-->'; #we may need to customize these begin and end tokens that we look for at some point, but for now these ones are pretty standard all across the board.
		my $end_token   = '<!--end_printable-->';
		
		#scrub the html for certain badness.
		my $badness = [
			qr/<TMPL_INCLUDE\s+name=.*?>/, #dont want to accidentally end up trying to include shit which doesnt exist from funny content in sitepilot templates. maybe there could be a special case some time where we dont want to do this becuase the thing exists and we really really want to include it that way! not yet.
		];
		foreach (@$badness) {
			$html =~ s|$_||g; #cool this totally works. 2007 06 03 updated with g option because it looks wrong without it.
		}
		
		if ($args->{exclude_original_content}) {
			$html =~ s|$begin_token(.*)$end_token|$begin_token <TMPL_INCLUDE $enclosure_tmpl> $end_token|s;
		} else {
			#mangles utf8 original page content....
			#$html =~ s|$begin_token(.*)$end_token|$begin_token $1 <br /><TMPL_INCLUDE $enclosure_tmpl> $end_token|s;
			#below is fix for the original page content getting mangled.
				#updated, is weird, sometimes $1 is already utf8! I totally do not fucking understand why sometimes it would be and other times not.
			$html =~ s|$begin_token(.*)$end_token|$begin_token . (Encode::is_utf8($1) ? $1 : Encode::decode("utf8", $1)) . "<br /><TMPL_INCLUDE $enclosure_tmpl>" . $end_token|se;
			$self->ch_debug(['source_template: utf flag on the html var after slapping in include for the enclosure tmpl?', Encode::is_utf8($html) ]);
		}
		
		if ($args->{head_insert}) {
			#$self->ch_debug(['here in templatesourcer to add head items:', );
			my $insert = join("\n", @{$args->{head_insert}}) . "\n";
			$html =~ s|</head>|$insert</head>|i;
		}
	}
	
	#$self->{wa}->debuglog(['templatesourcer: heres that html:, ', $html]);
	
	return \$html;	
}

### This one really should emply some kind of caching .... hrm . woul
sub get_page_content_slices {
	my $self = shift;
	my $args = shift;
	
	my $content_descriptors = $args->{content_descriptors};
	my $html_ref            = $args->{html_ref};
	my $source_html_from    = $args->{source_html_from};

	#if we're not caching, wipe the cache every time
	if ($self->{wa}->config('dont_cache_content')) {
		$_CONTENT_SLICE_CACHE = {};
		$_CONTENT_CACHE = {};
		#die "just cleared the content caches. Did you really want to do that?";
	}

	if (!$html_ref && $source_html_from) {
		#if we're asked to load from a file, cache the results.
		if ($_CONTENT_CACHE->{$self->{wa}->param('_app_id')}->{$source_html_from}) {
			$html_ref = $_CONTENT_CACHE->{$self->{wa}->param('_app_id')}->{$source_html_from};
			$self->{wa}->debuglog("get_page_content_slices: $$: using cached source content");
		} else {
			$html_ref = SpApp::TemplateSourcer->new($self->{wa})->source_template({ 
				source_file_processing => 0, 
				source_file            => $source_html_from,
			});
			$_CONTENT_CACHE->{$self->{wa}->param('_app_id')}->{$source_html_from} = $html_ref;
			$self->{wa}->debuglog("get_page_content_slices: $$: caching source content");
		}
	}
	
	#$self->ch_debug(['get_page_content_slices: the html to dig in is like:', $$html_ref ]);

	#the point of this is to go read a sitepilot page (ew) and suck out clearly marked bits of (named) content that we have been asked to get
	my $content_slices = {};
	foreach my $cntdsc (@$content_descriptors) {
		if (!$cntdsc->{name}) { die "cntdsc without a name"; }
		#if we're asked to load from a file, cache the results.
		my $slice_html = undef;
		if ($_CONTENT_SLICE_CACHE->{$self->{wa}->param('_app_id')}->{$cntdsc->{name}}) {
			my $slice_html_ref = $_CONTENT_SLICE_CACHE->{$self->{wa}->param('_app_id')}->{$cntdsc->{name}};
			$slice_html = $$slice_html_ref;
			$self->{wa}->debuglog("get_page_content_slices: $$: using cached slice named '$cntdsc->{name}'");
		} else {
			#we have to fish it out.

			my ($begin_token, $end_token) = (undef, undef);
			if ($cntdsc->{begin_token}) {
				$begin_token = "<!-- $cntdsc->{begin_token} -->";
			} else {
				$begin_token = "<!-- $cntdsc->{name} BEGIN -->";
			}
			if ($cntdsc->{end_token}) {
				$end_token = "<!-- $cntdsc->{end_token} -->";
			} else {
				$end_token = "<!-- $cntdsc->{name} END -->";
			}
			
			#$self->ch_debug(['get_page_content_slices: looking for tokens like: ', [$begin_token, $end_token], 'inside the html']);
	
			#match it to our tokens, grab the bit that matches.
			my @matching_content = ($$html_ref =~ m|$begin_token(.*)$end_token|s);
			$slice_html = $matching_content[0] ? $matching_content[0] : '<p>Tokens Error.</p>';			

			#now save it so we dont bother with that again.
			$_CONTENT_SLICE_CACHE->{$self->{wa}->param('_app_id')}->{$cntdsc->{name}} = \$slice_html;
			$self->{wa}->debuglog("get_page_content_slices: $$: caching slice '$cntdsc->{name}'");
		}

		$content_slices->{$cntdsc->{name} . '_html'} = $slice_html;
	}
	return $content_slices;
}
	

1;