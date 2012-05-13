package SpApp::TestSuite;
use base "SpApp::StandaloneUtil";
use WWW::Mechanize;

use strict;

#we have to test all our apps
# - AbriaChart
# - CMCEduSignup (USA, Can)
# - CMCReg
# - Edu R1
# - Edu R2


########## SETUP METHODS #############
sub _start_mode {
	return 'run_tests';
}

sub _runmode_map {
	my $self = shift;
	return {
		'run_tests'   => {},
	}
}

########## RUNMODE METHODS #############
sub run_tests {
	my $self = shift;
	my $args = shift;
	
	#Notes:
		#This is kind of the central repository for urls for all the various apps.
		#At the time of this writing, 2007 08 31, there are a few apps that are not listed here:
			# - BlumontChart
			# - BlumontAC (Access control system and disclaimer Handler)
			# - NCCFTF (Ncc Face The Facts - is basically a glorified formmail and log)
	
	#die "run tests!";
	##Without edusignup_can tests, we are back to 29.
	##use Test::Simple tests => 33;
	use Test::Simple tests => 29; 
	my $dev_urls = {
		edu_r2                      => 'http://cmcfxdev.spiserver3.com:10080',
		edu_r2_hit_lessontest       => 'http://cmcfxdev.spiserver3.com:10080/edu.pl?rm=show_begin_test&test_id=1&test_type=lesson',
		edu_r2_view_html_page       => 'http://cmcfxdev.spiserver3.com:10080/module3/lesson4/multiple_time_frame_analysis.html',

		abchrt                      => 'http://appdev.spiserver3.com:10080/abchrt.pl',
		abchrt_chartlist            => 'http://appdev.spiserver3.com:10080/abchrt.pl?rm=show_chart_list',
		abchrt_admin                => 'http://appdev.spiserver3.com:10080/abchrt_admin.pl',
		abchrt_admin_ds_common_list => 'http://appdev.spiserver3.com:10080/abchrt_admin.pl?rm=show_datasheet_common_list',

		#edusignup_can_form         => 'http://appdev.spiserver3.com/cmcedusignup_can.pl',
		edusignup_usa_form          => 'https://appdev.spiserver3.com:10443/cmcedusignup_usa.pl',
		
		#cmcedufree                 => 'http://chtest.spiserver3.com/cmcedufree.pl',
		cmcedufree                  => 'http://appdev.spiserver3.com:10080/cmcedufree.pl',
		
		cmcreg                      => 'http://cmccandev.spiserver3.com:10080',

		lbg_user                    => 'http://lbg.spiserver3.com:10080/lbg.pl',
	};

	my $mod_urls = {
		edu_r2                      => 'http://appmodel.spiserver3.com:9080/edu.pl',
		edu_r2_hit_lessontest       => 'http://appmodel.spiserver3.com:9080/edu.pl?rm=show_begin_test&test_id=1&test_type=lesson',
		edu_r2_view_html_page       => 'http://appmodel.spiserver3.com:9080/module3/lesson4/multiple_time_frame_analysis.html',

		abchrt                      => 'http://appmodel.spiserver3.com:9080/abchrt.pl',
		abchrt_chartlist            => 'http://appmodel.spiserver3.com:9080/abchrt.pl?rm=show_chart_list',
		abchrt_admin                => 'http://appmodel.spiserver3.com:9080/abchrt_admin.pl',
		abchrt_admin_ds_common_list => 'http://appmodel.spiserver3.com:9080/abchrt_admin.pl?rm=show_datasheet_common_list',

		#edusignup_can_form         => 'http://appdev.spiserver3.com/cmcedusignup_can.pl',
		edusignup_usa_form          => 'https://appmodel.spiserver3.com:9443/cmcedusignup_usa.pl', #fucking neccessitates the vhost_ssl in appdev. doh.
		
		#cmcedufree                 => 'http://chtest.spiserver3.com/cmcedufree.pl',
		cmcedufree                  => 'http://appmodel.spiserver3.com:9080/cmcedufree.pl',
		
		cmcreg                      => 'http://cmccanmod.spiserver3.com:9080', #already have this MOD vhost established.

		lbg_user                    => 'http://appmodel.spiserver3.com:9080/lbg.pl',
	};


	my $prod_urls = {
		edu_r2       => 'http://edu.cmcmarkets.ca',
		edu_r2_hit_lessontest => 'http://edu.cmcmarkets.ca/edu.pl?rm=show_begin_test&test_id=1&test_type=lesson',
		edu_r2_view_html_page => 'http://edu.cmcmarkets.ca/module3/lesson4/multiple_time_frame_analysis.html',

		abchrt       => 'http://abria.spiserver3.com/abchrt.pl',
		abchrt_chartlist => 'http://abria.spiserver3.com/abchrt.pl?rm=show_chart_list',
		abchrt_admin => 'http://abria.spiserver3.com/abchrt_admin.pl',
		abchrt_admin_ds_common_list => 'http://abria.spiserver3.com/abchrt_admin.pl?rm=show_datasheet_common_list',

		#edusignup_can_form => 'http://www.cmcmarketsfx.ca/cmcedusignup.pl',
		edusignup_usa_form => 'https://www.fxinabox.com/',

		cmcedufree => 'http://intranet.cmcmarkets.ca/cmcedufree.pl',

		cmcreg => 'http://cmcmarkets.ca',

		lbg_user => 'http://librarybuyersguide.com/lbg.pl',
		
	};
	
	my $testmode = $self->query()->param('testmode');
	if (!$testmode) {
		$testmode = 'dev';
	}
	my $all_urls = {
		'dev' => $dev_urls,
		'prod' => $prod_urls,
		'mod'  => $mod_urls,
	};
	if (!$all_urls->{$testmode}) { die "Invalid testmode $testmode"; }
	my $urls = $all_urls->{$testmode}; #so now operating off of dev or test urls.
	$self->dbg_print(["With Testmode of '$testmode', we're going to use these urls:", $urls]);
	print "Press enter to continue (or ctrl-c to bail)";
	my $pause = <STDIN>;
	
	$self->edu_r2($urls);
	$self->abriachart($urls);
	
	###Commenting out edusignup_can tests as this app is no longer in service and there is no PROD url for it at the moment (2007 06 12)
	#$self->edusignup_can($urls);
	
	$self->edusignup_usa($urls);
	$self->cmcedufree($urls);
	$self->cmcreg($urls);
	$self->lbg($urls);
	
	return "Job Complete";
}

sub edu_r2 {
	my $self = shift;
	my $urls = shift;
	
	my $mech = WWW::Mechanize->new( autocheck => 1 );
	
	#so this shit worked. Since all our client side code uses js to submit the forms, we'll have to populate the vars that are being controlled manually here.
	#and we can probably defined loops to do stuff with params, hit runmodes with params is really what we're on about here. some direct url access to check handlers and rewrite rules etc, whatever is needed this WWW::Mechanize thing seems to be pretty damn slick and functional!
	
	print "Edu App:\n";
	my $start_url = $urls->{edu_r2};
	$mech->get($start_url);
	
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'process_login',
			login_username => 'edutest',
			login_password => 'edutest',
		},
	);
	ok($mech->content() =~ /EduTest the 3rd, Esquire CourseWare, welcome./, 'logged in successfully');

	#browse to a lesson test.
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'show_course',
			course_id => 1,
		},
	);
	#die "must verify that we saw something proper on this screen. whatever we should get after clicking 'skip intro'";
	ok($mech->content() =~ /Module&nbsp;Name/, 'viewed course modules list');
	
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'show_module',
			module_id => 1,
		},
	);
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'show_begin_test',
			test_id   => 1,
			test_type => 'lesson',
		},
	);
	#lesson test could be asking a q or telling you that you answered all the q and its time to score. if we dont get either of those variations, we be borked.
	ok( ($mech->content() =~ /Click Here to Score Your Test/) || ($mech->content() =~ /Skip this Question/), "browsed to a lesson test" );

	#while logged in, go view a html page, that for some reason we get a cookie problem error sometimes. (? not sure on this?)
	$mech->get($urls->{edu_r2_view_html_page});

	ok( $mech->content() =~ /This strategy of FX trading requires identifying a major trend and trading with a bias towards that longer term trend, regardless of the timeframe of the trader/ , "browsed to a specific html page" );

	#log out, try to go back, see login screen.
	$mech->get('/logout.html');
	$mech->get($urls->{edu_r2_hit_lessontest});
	ok ($mech->content() =~ /Username.*Password/s, 'access test after logout, shows login page');

	#log in with bad userinfo, be blocked.
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'process_login',
			login_username => 'bozo',
			login_password => 'bozo',
		},
	);
	ok ($mech->content() =~ /Bad login. Please try again./, 'login with bad info is blocked');
	print "Edu R2 Tests Complete\n";
}

sub abriachart {
	my $self = shift;
	my $urls = shift;

	my $mech = WWW::Mechanize->new( autocheck => 1 );
		
	print "AbriaChart App:\n";
	#user side stuff
	$mech->get($urls->{abchrt_chartlist});
	ok($mech->content() =~ /ADAF Class B/, 'userside: output contained expected string');
	ok($mech->follow_link( text => "HTML", url_regex => qr/show_datasheet/, n => 1 ), 'userside: followed first html data sheet link'); #first link called HTML, should be a data sheet html rendering.
	ok($mech->content() =~ /<!--Blue Seperator Bar Start-->/, 'userside: content contained a blue separator bar comment (must be the right output then eh)'); #check for some content that should always appear in the html of a data sheet. lol and separator is speeld wrong.

	#admin side stuff
	$mech->get($urls->{abchrt_admin});
	ok($mech->content() =~ /Username.*Password/s, 'adminside: got login screen');
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'process_login',
			login_username => 'chagglund',
			login_password => 'snafu7',
		},
	);
	ok($mech->content() =~ /Export Chart Data as \.xls/, 'adminside: logged in as Chris, got main menu screen');
	$mech->get($urls->{abchrt_admin_ds_common_list});
	ok($mech->content() =~ /Contact 1/, 'adminside: viewing datasheet common list');
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'show_datasheet_common_form',
		},
	);
	ok($mech->content() =~ /Cutsheet Common Text/, 'adminside: viewing form for New cutsheet common text');

	print "AbriaChart Tests Complete\n";
}

sub edusignup_can {
	my $self = shift;
	my $urls = shift;

	my $mech = WWW::Mechanize->new( autocheck => 1 );
		
	print "CMCEduSignup CAN App:\n";
	$mech->get($urls->{edusignup_can_form});
	ok($mech->content() =~ /Fields marked with \* are mandatory/, 'obtained the signup form');
	my $randomstr = $self->random_string({len=>16});
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'process_signup',
			es_first_name => 'testfirstname',
			es_last_name  => 'testlastname',
			es_address1   => '123 Fake Street',
			es_city       => 'SPITown',
			es_state_id   => 7,
			es_postal     => '123SPI',
			es_country_id => 38,
			es_phone      => '11234525',
			es_signup_email => $randomstr . '@chtest.spiserver3.com',
			reenter_email   => $randomstr . '@chtest.spiserver3.com',
		},
	);
	ok($mech->content() =~ /Please wait while you are sent to secure payment server/, 'submitted a good form, got to the worldpay auto-post form');
	$mech->get($urls->{edusignup_can_form});
	ok($mech->content() =~ /Fields marked with \* are mandatory/, 'obtained the signup form again');
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'process_signup',
		},
	);
	ok($mech->content() =~ /Fields marked in red contain errors./, 'bad submission returned form in retry-mode.');

	print "CMCEduSignup CAN Complete\n";
}

sub edusignup_usa {
	my $self = shift;
	my $urls = shift;

	my $mech = WWW::Mechanize->new( autocheck => 1 );
		
	print "CMCEduSignup USA App:\n";
	$mech->get($urls->{edusignup_usa_form});
	ok($mech->content() =~ /Fields marked with \* are mandatory/, 'obtained the signup form');
	
	my $randomstr = $self->random_string({len=>16});
	use Time::Piece;
	my $tp = localtime;
	my $year = $tp->year() + 3;
	
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'process_signup',
			es_course_type => 'full',
			es_first_name => 'testfirstname',
			es_last_name  => 'testlastname',
			es_address1   => '123 Fake Street',
			es_city       => 'SPITown',
			es_state_id   => 100,
			es_postal     => '123SPI',
			es_phone      => '11234525',
			es_how_heard  => 4,
			es_signup_email => $randomstr . '@chtest.spiserver3.com',
			cc_type => 1,
			cc_num  => '4444333322221111',
			cc_exp_mo => 1,
			cc_exp_yr => $year, 
			cc_id     => '1234',
			cc_name   => 'test cc guy',
		},
	);
	ok($mech->content() =~ /Course Enrollment Confirmation/, 'submitted a good form, got to the confirmation scree');
	$mech->get($urls->{edusignup_usa_form});
	ok($mech->content() =~ /Fields marked with \* are mandatory/, 'obtained the signup form again');
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'process_signup',
		},
	);
	ok($mech->content() =~ /Fields marked in red contain errors./, 'bad submission returned form in retry-mode.');

	print "CMCEduSignup USA Complete\n";
}

sub cmcedufree {
	my $self = shift;
	my $urls = shift;

	my $mech = WWW::Mechanize->new( autocheck => 1 );

	print "CMCEduFree App:\n";
	$mech->get($urls->{cmcedufree});

	#hit login screen
	ok ($mech->content() =~ /Username.*Password/s, 'reach login page');

	#post form with good userinfo and be logged in
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'process_login',
			login_username => 'cmc',
			login_password => 'edufree',
		},
	);
	ok ($mech->content() =~ /Please fill out our registration form to complete your request/, 'reach enrollment form');
	
	#go to choose the Course
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'show_signup_courses',
			signup_form_submission => 1,
		},
	);
	ok ($mech->content() =~ /To enroll, select a course offering above and click the enroll button/, 'reach course selection form');

	#select the Course, and ensure its name appears when we get back to the form.
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'set_signup_form_items',
			course_package_id => 1,
			courses_list_submission => 1,
		},
	);
	ok ($mech->content() =~ /Trading Foreign Exchange/, 'returned to form - selected course name now appears');
	
	#submit the form with everything filled out. randomize email., ok if we get the reg-complete confirmation.
	my $randomstr = $self->random_string({len=>16});
	$mech->tick( 'followups', 2 );  #Offering Education as a Sales Incentive,
	$mech->tick( 'followups', 4 );  #Provide for Internal Purposes
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'process_signup',
			signup_form_submission => 1,
			first_name   => 'testfirstname',
			last_name    => 'testlastname',
			email        => $randomstr . '@cmcmarkets.com',
			retype_email => $randomstr . '@cmcmarkets.com',
			phone        => '123TEST',
			office       => 6, #london
			howheard     => 3, #CMC Markets Intranet
			#followups    => #woops can't do cboxes here.
		},
	);
	#$self->dbg_print([$mech->content()]); #ahha interface string was different dev vs prod. it did succeed.
	ok ($mech->content() =~ /Registration Complete/, 'completed enrollment and see confirmation message');

	print "CMCEduFree Complete\n";
}

sub cmcreg {
	my $self = shift;
	my $urls = shift;

	my $mech = WWW::Mechanize->new( autocheck => 1 );

	print "CMCReg App:\n";
	#hit index page
	$mech->get($urls->{cmcreg});
	ok ($mech->content() =~ /Examples used are for illustrative purposes only and not to be misunderstood as a recommendation/s, 'view home page');

	#hit a page that should present a login form.
	$mech->get($urls->{cmcreg} . '/free_sample_strategy_guide.html');
	ok ($mech->content() =~ /Email Address:/s, 'receive login page');

	#post login form with a random email, should receive the signup form.
	my $random_email = $self->random_string({len=>16}) . '@chtest.spiserver3.com';
	$mech->submit_form(
		form_name => 'main_form',
		fields    => {
			rm => 'process_login',
			login_email => $random_email,
		},
	);
	ok ($mech->content() =~ /The email $random_email is not in our records/, 'reached signup form');

	print "CMCReg - thats enough for now.\n";
}

sub lbg {
	my $self = shift;
	my $urls = shift;

	my $mech = WWW::Mechanize->new( autocheck => 1 );

	print "LBG App:\n";
	#hit index page
	$mech->get($urls->{lbg_user});
	ok ($mech->content() =~ /Company Listings/s, 'view default runmode (show_company_list)');

	#show the advanced search page..
	$mech->get($urls->{lbg} . '?rm=show_company_advancedsearch&reset=1');
	ok ($mech->content() =~ /Advanced Search/s, 'view advanced search');
	
	#search for "book" and make sure there are results.
	my $an_expected_item = 'ABI Professional Publications'; #just hardcoding some item that should be in the results list as of 2007 06 12 .. this will fail if that item disappears from the list and we'll have to update it with something else.
	$mech->form_name('main_form');
	$mech->field('keywords', 'book');
	$mech->field('new_search', 1);
	$mech->field('rm', 'show_company_advancedsearch');
	$mech->submit();
	ok ($mech->content() =~ /$an_expected_item/s, 'perform advanced search, find expectged result');
	
	#follow the link on that item.
	$mech->follow_link( text => $an_expected_item );
	ok ($mech->content() =~ /PRODUCTS & SERVICES BY THIS COMPANY/s, 'viewed company details');

	print "LBG - thats enough for now.\n";
}
1;