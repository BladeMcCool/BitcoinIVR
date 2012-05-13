package SpApp::DataObj::Relator;
use base "SpApp::DataObj";
use strict;

our $AUTOLOAD;  # it's a package global ... http://perl.active-venture.com/pod/perltoot-autoload.html

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_); #I had it close, merlyn on #perl got me straightened. From the reading that had me almost having it right, I know why this works. $class is the package name, and that is how to call it dynamically. I could have hardcoded some SpApp::DataObj::Object too, but that would of course be pointless and work only for the one.

	$self->{_relations} = {};
	$self->relate();
	return $self;
}

#sub error {
#	my $self = shift;
#	my $value = shift;
#	
#	if ($value) {
#		$self->{_ERROR_COND} = $value;
#		die "SpApp::DataObj::Relator Error: $value";
#	} else {
#		return $self->{_ERROR_COND};
#	}
#}

###not so sure I want to die if subclass didnt define. just return empty arrayref.
#sub _relationships { die "No _relationships func defined while using SpApp::DataObj::Relator?"; return undef; }; #to be overridden by subclass.
sub _relationships { return []; }; #to be overridden by subclass.

### example relationships (this may need work and is just me trying to note what I remember)
## { has_many => 'Some::DataObj::Classname',     our => 'record_id', their => 'some_other_field' }
## { has_a    => 'my_relationship',              our => 'thing_id',  their => 'record_id', classname => 'Some::DataObj::LongWindedClassName' }
## { has_a    => 'my_relationship',              our => 'thing_id',  their => 'record_id', classname => 'LongWindedClassName' } #classname should be prefixed with Some::DataObj:: automatically.
## { has_a    => 'automatic_classname_resolver', our => 'thing_id',  their => 'record_id',  } #would be class Some::DataObj::AutomaticClassnameResolver

sub relate {
	my $self = shift;
	my $args = shift;
	
	my $relationships = $self->_relationships();
	return if !$relationships; #abort if there is no mission.
	
	#golly, I guess the first thing we need to to is load a record. we can't be related to anything if we dont know anything about ourself.
	$self->{wa}->ch_debug(['relate: here with:', $relationships]);
	
	foreach my $relationship (@$relationships) {

		my $our_field   => $relationship->{our}; #the field in our table that has to be equal to 
		my $their_field => $relationship->{their}; #the field in their table
		my $type = $relationship->{has_a}    ? 'has_a' : 
               $relationship->{has_many} ? 'has_many' :
               die "undefined relationship type";


		#lets xform the has_a relationships into object name mappings
		(my $package_hierarchy = ref($self)) =~ s|::(\w)*$||; #chop the ::Whatever off the end ..

		#related object classname ...
		if (!$relationship->{classname}) {
			#if not given explicit classname, figure it out
			(my $related_package = $relationship->{$type}) =~ s/(?:_|\b)(\w)/\u$1/g; #title case. hacked. (?:) is just grouping. _|\b is matching either a underscore or a \b wordboundary assertion ... \u$1 is uppercasing the first char of $1. ... http://www.perl.com/doc/manual/html/pod/perlre.html ... oh and assigned in parens to not mess with $relation.
			my $relation_classname = ($related_package =~ /::/) ? $related_package : $package_hierarchy . '::' . $related_package;
			$relationship->{classname} = $relation_classname;
			$self->{wa}->ch_debug(['fished out a relation classname: ', $relation_classname, 'possibly using a related_package:', $related_package ]);
		} elsif ($relationship->{classname} !~ /::/) {
			#2007 08 21 
			#or given partial classname (perhaps classname is just the bit that comes after the apps common data object package hierarchy? (as in there is a classname but it doesnt include any ::) then we can just prepend the goodness we will assume.)
			$relationship->{classname} = $package_hierarchy . '::' . $relationship->{classname};
		}			
		
		$relationship->{type}      = $type; #has_a, or has_many

		#relation name (what function we'll have to call to get the related objects/records) ...
		my $relation_name = $relationship->{$type};
		if ($relation_name =~ /::/) {
			#we've been given a full package name to relate to. but we need a short name for the relation.
			$relation_name =~ s/.*://;   # strip fully-qualified portion
			#split on capitals and lower case them ... xform SillyHatWearer to silly_hat_wearer
			$relation_name =~ s|([A-Z])|_\L$1\E|g; #go from SomethingLikeThis to _something_like_this
			$relation_name =~ s|^_||; #then lose that underscore prefix (can't figure out how to do it all in one regex).
		}
		#differentiate between single and many relationship types by giving more descriptive accessor.
			#so you will access things like: get_hat or get_many_hat
		if ($type eq 'has_many') {
			$relation_name = 'many_' . $relation_name;
		}
		$self->{_relations}->{$relation_name} = $relationship;

		$self->{wa}->ch_debug(['relate: setting up with:', {hierarchy => $package_hierarchy, relation_name => $relation_name, relationship => $relationship }]);

	}
	
	$self->{wa}->ch_debug(['relations:', $self->{_relations}, ref($self), "$self"]);
	
}

#handle dynamic method naming with AUTOLOAD, which is handier for this than the still VERY interesting dynamic subroutine stuff we tried before.
sub AUTOLOAD {
	my $self = shift;
	my $args = shift;
	
	my $name = $AUTOLOAD;
	my $valid = 0;
	if ($name =~ /get_/) { $valid =  1; }		
	if (!$valid) { die "invalid AUTOLOAD method $name - did you just change the obj to subclass Relator? Does apache/mod_perl know that?"; } 
	
	$self->ch_debug(["in AUTOLOAD for $name"]);

	if (!$self->record_id()) {
		$self->error('Cannot obtain related records when I dont even know who I am. (no record_id set)');
		$self->ch_debug(["relator autoload: 'Cannot obtain related records when I dont even know who I am. (no record_id set)'"]);
		return undef; #if the error was nonfatal heh.
	}
	
	#just for clarity of calling, i am going with get_foo and get_many_foo for has_a and has_many relation calling. toyed with idea of adding letter 's' to pluralize for get_many, but I dont like the semantics of it, especially for names that already end in s.
	
	$name =~ s/.*:get_//;   # strip fully-qualified portion so we'll be left with 'foo' or 'many_foo' or some such. 

	$self->ch_debug(["in AUTOLOAD and going to try to find a relation named $name among these:", $self->{_relations}, ref($self), "$self"]);

	my $relationship = $self->{_relations}->{$name};
	my $obj_class = ref($self);
	if (!$relationship) {
		die "AUTOLOAD: Unknown relationship for $name in object class $obj_class - is that relationship defined, or was your call in error?";
	}
	
	if ($relationship->{type} eq 'has_a') {
		return $self->get_a_relation($name, $args);
	}
	if ($relationship->{type} eq 'has_many') {
		return $self->get_many_relations($name, $args);
	}
}

#this will be to load some other related dataobject and find a single record for edit.
sub get_a_relation {
	my $self = shift;
	my $relation = shift;
	my $args = shift;
	
	my $relationship = $self->{_relations}->{$relation};
	my $related_d_obj = ($relationship->{classname})->new($self->{wa});
	my $our_field_value = $self->get_values({$relationship->{our} => 1}, { single_value => 1});
	if (!$our_field_value) { return undef; } #can't relate if we dont have a value on our half of the relationship.
	
	#get the record where their field equals our field.
	$self->ch_debug(['get_has_a_relation: their_param, our_param, our_value', $relationship->{their}, $relationship->{our},      ]);
	
	$related_d_obj->find_record_for_edit({ criteria => { $relationship->{their} => $our_field_value } });
	if (!$related_d_obj->record_id()) {
		return undef; #i dont think it makes sense to send back an object if it didnt find a record. -- it would not be related, it would be blank. maybe we'll want to do a new_has_a_relation or something later.
	}
	
	return $related_d_obj;
}

#this will be to load references to a bunch of other related objects or some shit.
	#not sure how this should work. going with matching search results for now. will have to call load_record_for_edit with one of their ids.
	#oooor i could be bloatytastic and actually load the many related records for edit? and when that starts getting slow then it becaomse time to start caching sql statements and/or doing prepare_cached with them or something that I'd want to benchmark performance of before and after.
	#lets do the scary thing that is going to really do what we probably really would love to do but which frightens us due to implications over existing ineffieciencies that can be improved upon.
sub get_many_relations {
	my $self = shift;
	my $relation = shift;
	my $args = shift;
	
	my $relationship = $self->{_relations}->{$relation};
	
	#going to make a dataobj for every related record and return them as a hashref with record_id as keys.
		#as of 2007 03 24 this will be VERY inefficient (will run thruogh sql build process ni every one and prepare statements again for each), but oh so neato, so who cares.
	#first find the related record ids using the related object class.
	##This way of getting our field value only will work if the field that we are relating with is marked as edit_show_field. unacceptable. And theres nothing wrong with get_values being like that ... its just not the way to access the value we want. I think I want to refer to fieldrefs instead.
		##I suspect I'm going to need to totally rework the internals of searchform/editform/general fields lists and stuff, I think I should always have access to all the base values of all the fields in the query.
		##Fortunately for the case where I find myself thinking "oh shit" I can use the record_id pseudo param.
	
	#2008-09-19 experiment for more complex relation based based on more than one field value - will use the full restrictor api if we see "restrict" as a key in the relationship.
	my $search_params = {
		restrict_options =>	{ dont_match_looked_up_values => 1, }, #I am pretty sure I will never want to relate based on a looked up value, and will always wnat to use the underlying value.
	};
	if ($relationship->{matched_by}) {
		#possibly multiple conditions
		#eg: matched_by => [{ our => 'record_id', their => 'vtreg_user_id'}, { their => 'resource' literal => 'demoacct'}]
		my $restrict = {};
		foreach my $cond (@{$relationship->{matched_by}}) {
			if ($cond->{our}) {
				my $our_field_value = $self->get_values({$cond->{our} => 1}, { single_value => 1});
				$restrict->{$cond->{their}} = $our_field_value;
			} elsif ($cond->{literal}) {
				$restrict->{$cond->{their}} = $cond->{literal};
			}
		}
		$search_params->{restrict} = $restrict;
		
	} else {
		#simple original way of doing it
		my $our_field_value = $self->get_values({$relationship->{our} => 1}, { single_value => 1});
		$search_params->{restrict} = { $relationship->{their} => $our_field_value };
	}
	
	#I dont think I want to accept search params wholesale, I think I want to allow a certani subset (which keeps fuckin growing) of options.
		#and some of the arg names will be translated (because certain names sound better in different contexts, like sort_relations vs user_sort!)
	if ($args->{sort_relations})  { $search_params->{user_sort}       = $args->{sort_relations};	}
  if ($args->{page_size})       {	$search_params->{page_size}       = $args->{page_size};	}
  if ($args->{record_id_param}) {	$search_params->{record_id_param} = $args->{record_id_param};	}
  if ($args->{short_text})      {	$search_params->{short_text}      = $args->{short_text};	}
  if ($args->{plaintext_html})  {	$search_params->{plaintext_html}  = $args->{plaintext_html};	}

	#continuing the 2007 05 09 experiment for valuesearched results that havent been saved yet displaying along with actually saved and already related records .... lets allow the addition of restrictor groups here.
	if ($args->{include_extra_records_with_restrictor_group}) {
		my $restrict = $search_params->{restrict};
		if (ref($restrict) ne 'ARRAY') { $restrict = [ $restrict ]; }
		push(@$restrict, $args->{include_extra_records_with_restrictor_group});
		$search_params->{restrict} = $restrict;
	}
		
	$self->ch_debug(['get_many_relations: about to query related object using this search_params', $search_params ]);

	my $related_results = ($relationship->{classname})->new($self->{wa})->get_search_results($search_params);
	my $records_simple  = $related_results->{records_simple};
	$self->ch_debug(['get_many_relations: going to set up relations for related objects based on these related_results:', $related_results ]);
	
	#2007 04 04 give a way to just get the search results for the related objects.
	if ($args->{records_simple}) {
		return $records_simple;
	}
	if ($args->{related_results}) {
		return $related_results;
	}

#	my $related_objs = {};
#	foreach (@$related_results) {
#		$related_objs->{$_->{record_id}} = ($relationship->{classname})->new($self->{wa})->load_record_for_edit({ record_id => $_->{record_id} });
#		$self->ch_debug(['getting the related recoreds, one with a record id:', $_->{record_id}, 'its edit values are:', $related_objs->{$_->{record_id}}->get_edit_display_values() ]);
#	}
	#2007 04 03 make this a arrayref instead. i think that should be the default behavior. maybe do what we were doing before as some kind of optional hashref of objs behavior, and could make it more flexible like you can choose what fieldparam to use for keys or something handy.
	my $related_objs = [ map { ($relationship->{classname})->new($self->{wa}, { record_id => $_->{record_id} }); } @$records_simple ];

	return $related_objs; #smooothe.
}

sub setup {}; #prevent errors even when abused.

#playing with dynamic sub refs:
#sub tacos {
#	my $self = shift;
#	my $function_name = shift;
#
#	#$function_name = "SpApp::DataObj::Relator::get_" . $function_name;
#	$function_name = "get_" . $function_name;
#	{ 
#		no strict 'refs';
#		#*{ $function_name } = sub { return "this is gay - but it works."; };
#		*{ $function_name } = \&foolatta;
#	}
#	
#	return "taco return";
#}
#
#
#sub foolatta {
#	my $self = shift;
#
#	return "this is gay - but it works like yo mama."; 
#}
#			#create functions!
#			{ 
#				no strict 'refs';
#				*{ 'get_' . $relationship->{has_a} } = eval <<HAS_A_GET
#				sub { 
#					my \$self = shift;
#					#for these I think we will want to return a loaded up related object, so we'd want to pass it a record id. to know what its id is, we need to know by what field of ours relates to this other object's ID.
#					return $package_name->new(\$self->{wa});
#				};
#HAS_A_GET
#			}
#			die $@ if $@;

1;