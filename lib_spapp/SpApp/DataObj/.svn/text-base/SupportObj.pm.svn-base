package SpApp::DataObj::SupportObj;
use strict;
use Scalar::Util qw(weaken);

sub new {
	my $invocant = shift;
	my $class    = ref($invocant) || $invocant;  # Object or class name
	my $self = {};
	bless $self, $class;

	my $data_obj = shift; #needed for access to stuff, including ->{wa} for a webapp!
	my $other_args = shift; #should be a ref to the DataObj::new constructor $other_args

	if (!$data_obj) {
		$self->error('new needs a data_obj.');
	}
	$self->{'do'} = $data_obj; #'do' is just shorthand for DataObj.
	$self->{wa} = $data_obj->{wa};
	weaken($self->{'do'}); #2011 01 13 attempt to resolve memory leak (part 2 of 3);
	weaken($self->{wa});   #2011 01 13 attempt to resolve memory leak (part 2 of 3);

#	$self->{emi}  = SpApp::DataObj::EditModeInternals->new($data_obj); #for internal support function acceess. 

	return $self;
}

#this _support_obj_init must be called by the DataObj, once for each support object, after all the them have been instantiated.
sub _standard_init {
	my $self = shift;
	my $objrefs = shift;
	my $args = shift;
	my $data_obj_constructor_args = shift;
	
	#i just dont think its _clean_ to keep a ref to whatever particular object is being set up inside that same object, so each time we do this, skip any objref keys that are included in the dont_ref arg.
	my $dont_ref = $args->{dont_ref};
	
	foreach (keys(%$objrefs)) {
		next if $dont_ref->{$_};
		#$self->ch_debug(['doing support _support_obj_init. setting up a ref at this key:', $_, 'dont ref is:', $dont_ref]);
		$self->{$_} = $objrefs->{$_};
		weaken($self->{$_}); #2011 01 13 attempt to resolve memory leak (part 3 of 3);
	}
	
	$self->_custom_init($objrefs, $data_obj_constructor_args);
}

#_custom_init can be overridden in the subclass to do extra stuff once all support object refs are set up. .. (like maybe set up custom sub-support objs, as is the reason it is being added for EditMode to give itself and EditModeInternals!)
#ALL PRIMARY SUPPORT OBJECT REFS MUST BE SET UP BEFORE CALLING the overridden _custom_init!
sub _custom_init { 
	my $self = shift;
	my $objrefs = shift; #reference to hashref of { tag => objref };
	my $data_obj_constructor_args = shift; #a ref to the $other_args built up in the DataObj::new().
	return undef; 
}

sub error {
	my $self = shift;
	return $self->{'do'}->error(@_);
}
sub clear_error {
	my $self = shift;
	return $self->{'do'}->clear_error(@_);
}

sub ch_debug {
	my $self = shift;
	return $self->{'do'}->ch_debug(@_);
}

sub DESTROY {
	#attempting to figure out some memory bloat issue, it was suggested that circular references can lead to the GC not being able to deallocate memory. now I _know_ i have effectively circular references in this code in that we have refs to the support objects and they all have refs back to us (their ->{'do'})
	my $self = shift;
	
	#die "really here in support obj";
	#$self->{wa}->debuglog(['here1 in destroy of supportobj']);
	return 1;
}

1;