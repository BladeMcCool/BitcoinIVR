#!/usr/bin/perl
use strict;
use lib '/home/ubuntu/spapp_dev/lib_spapp';
$| = 1;
BEGIN {
	use Carp;
	$SIG{__WARN__} = \&carp;
	$SIG{__DIE__} = \&confess;
	
	$ENV{PERL_NET_HTTPS_SSL_SOCKET_CLASS}='Net::SSL'; #7 hours later to find that this class is important for proper https proxying. And then a protip from Khisanth to read the first 10 lines of Net::HTTPS a little closer. ;) oh and then another hour to realize this needs to be in the BEGIN block or something if the modules are already loaded by other things (my hax modules were getting loaded later i guess?? dunno but this makes it work!)
	$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0; #this can go here too.
}

my $helper = BTCSys::CmdLine->new(PARAMS => { '_app_name' => 'btcsys', config_path => '/etc/asterisk/phoneapp/conf/phoneapp.conf' });
$helper->run();
	
1;

################
package BTCSys::CmdLine;
use strict;
#use base ("CaptchaQuest::SeoMoz",'CaptchaQuest::Core',"SpApp::StandaloneUtil");
use base ("SpApp::StandaloneUtil");
use Time::Piece::MySQL;
use Asterisk::AGI;
use Digest::FNV qw(fnv);
use CaptchaQuest::BTCDataObjects;
use JSON::RPC::Client;
use File::Basename;
use Digest::MD5 qw(md5_hex);

use constant ALLDIG => '*#0123456789';

#todo . double salt and sha256 the pin numbers :)

#also, maybe good idea to track tx in our own ledger? 

#need to understand how that one account became negative. how to predict the fee that will be charged ???? cuz we need to predict the fee to know if customer has enuogh balance!
	#bitcoind 'undocumented features' lol.
	#maybe find a way to take a small system fee from users of 0.002 btc or something to cover this bullshit? or hack the code and run a hacked bitcoind.
	#or likely until this bug is resolved i need to store some extra btc in the system to cover fees.
	
#track login attempts over time and lock acocunts for 1 hour if 5 failed login attempts in 5 minutes.
#ability to change BTC address
	#we _could_ track prior ones, .... but bitcoind _will_ track them and should apply the tx to the correct account.

sub _start_mode {
	#return 'logged_in_redirect';
	return 'main_loop';
}
sub _runmode_map {
	my $self = shift;
	return {
		#'restricted_example' => {rm_sub=>'subname_can_differ', level=>20, auth_subref=>\&_some_bool_returning_subref, rsf=>['has_passed_test1','has_passed_test2']}, #rm_sub is different from rm name, not public (no pub=>1 present), min userlevel 20, and even then still has to pass credential check in a user function called (in this case) _check_restricted_mode_credentials, and also has to have two (in this case) specific session flags set.
		'main_loop'  => {pub=>1}, 
		'debug_explore' => {pub=>1}, 
	};
}

sub main_loop {
	my $self = shift;
	
	$SIG{HUP} = sub { $self->_teardown(); };

	my $AGI = Asterisk::AGI->new();

	my %input = $AGI->ReadParse();

	$self->debuglog(\%input);

	my $userobj = CaptchaQuest::BTCDataObj::BTCSysUser->new($self); #->create_table({alter=>1});

	#my $lol = $AGI->exec('Festival',"'what is the format of this i must repeat myself so that there is enough time 0123',".ALLDIG);
	#my $lol = $AGI->exec('Festival',"what is the format of this i must repeat myself so that there is enough time 0123,".ALLDIG);
	#$AGI->exec('Festival',"Taco trucks are fucking awesome");
	#my $lol = $AGI->stream_file('phoneapp/Capital', ALLDIG); #'press any button to acknowledge your shit';

	#$self->debuglog(['did you hear it?', $lol ]);
	#die "stop here";
	#debug
	#$userobj->load(17); #someone with some money :)
	#$self->customer_menu({agi=>$AGI, userobj=>$userobj} );
	#end debug.
	#my $wacky = '1n2873re09jvh322t89h0';
	#my $debugtest = "Debug <break time='2500ms'/> testing text to speech for Transaction ID starting " . join('; ', split(//,substr(uc($wacky), 0, 3))) . ' and ending ' . join('; ', split(//,substr(uc($wacky), -3)));
	#probably goiing to have to use that sable markup to get it to speak the starting-with ending-with letters stuff correctly due to its internal processing of single vowel letters like A at the end of the string (cannot get it to reliably pronounce ALL the letters AND have consistent timing between reading each letter).
	# my $debugtest = "test; Letter A, B, A, ;";
	# my $foo = $self->get_speak_data({ agi => $AGI, text => $debugtest });
	# my $debugtest = "test; Letter A, B, A,";
	# my $foo = $self->get_speak_data({ agi => $AGI, text => $debugtest });
	# my $debugtest = "test; Letter A - B - A -";
	# my $foo = $self->get_speak_data({ agi => $AGI, text => $debugtest });


	my $speech = "Please enter your syscode user identification number now. If you do not have a syscode user identification number, you can obtain one by pressing the pound sign on your keypad now. Your syscode number is the number you can use to identify yourself to other btc sys users as well. If you have forgotten your user information there is currently no other way for us to identify you. This system is experimental and no bitcoin balances are stored outside of our main wallet file. Use this system at your own risk. We will not be held liable for any losses or damaages related to your use of this service. Thank you for helping us alpha test our prototype bitcoin IVR system.";
	#my $speech = "Debug intro text is much shorter.";
	my $keep_connected = 1;
	
	while ($keep_connected) {
		#prompt 'enter your account number or press pound to create a new account;
		
		#my $debug = $self->festival_speak({ agi => $AGI, text => "wouldn't it be nice to hear the sound of Festival text to speech?" });
		
		##rewite:
		#speak the main speech prompt. with baildicator.
		#did user enter some numbers? great, auth them and send to customer menu if so.
			#if we come out of customer menu, undef loggedin_userid since they dont want to be that customer any more.
				#and clear userobj record id at that time.
		#no? did user enter the baildicator only?
			#then enter new customer process.
		#or nothing at all? loop again!
		
		my $userid = $self->get_speak_data({ agi => $AGI, text => $speech, timeout => 15000, chars => 10, baildicator => 1, morechars_requires_firstchar => 1 });
		if (defined($userid)) {
			$userobj->clear_record_id();
			if ($userid eq '#') {
				$self->newuser_process({agi=>$AGI, userobj=>$userobj } );
				$self->debuglog(['after newuser_process, userobj record id and loggedinuserid: ', $userobj->record_id() ]);
			} elsif ($userid =~ /^\d+$/) {
				my $pin = $self->get_speak_data({ agi => $AGI, text => 'Enter pin then pound.', timeout => 15000, chars => 10 });
				#my $pin = $AGI->get_data('conf-getpin', 15000, 10);
				$self->debuglog(['user entered this id/pin: ', $userid, $pin ]);
				if (!defined($pin)) { 
					#my $acked = $AGI->exec('Espeak',"'We did not receive your response.',".ALLDIG);
					my $acked = $self->festival_speak({ agi=>$AGI, text => 'We did not receive your response.' });
					$acked ||= $AGI->wait_for_digit(1500);
					next; 
				}
				
				$userobj->find({ criteria => { userid => $userid, pin => $pin }});
				if (!$userobj->record_id()) { 
					#my $acked = $AGI->exec('Espeak',"'We are sorry but we could not authenticate you using the credentials you supplied.',".ALLDIG);
					my $acked = $self->festival_speak({ agi=>$AGI, text => 'We are sorry but we could not authenticate you using the credentials you supplied.' });
					$acked ||= $AGI->wait_for_digit(1500);
					next; 
				}
				$self->debuglog(['looks like a legit user' ]);
			}
			#userobj as an id? good we are a legit user lets have the cx menu.
			if ($userobj->record_id()) {
				$self->customer_menu({agi=>$AGI, userobj=>$userobj} );
			}
		} else {
			#no data entered? SLEEP (accept no input during that deadtime) then reprompt for it! lol.
			sleep(2);
			next;
		}

	}
	
	$self->debuglog(['tiime to hang up.']);
	#$AGI->stream_file($chopped, '0123');
	$AGI->stream_file('vm-goodbye');
	$AGI->hangup();
	
		# #next; #loop forever IMO.
		
		
		# if (!$loggedin_userid) {
			# $userobj->clear_record_id();
			# #my $userid = $AGI->get_data('privacy-prompt', 15000, 10);
			
			# #my $userid = $self->get_speak_data({ agi => $AGI, text => $speech, timeout => 15000, chars => 10, baildicator => 1, morechars_requires_firstchar => 1 });
			# my $userid = $self->get_speak_data({ agi => $AGI, text => $speech, timeout => 15000, chars => 10 });
			# $self->debuglog(['user entered this id: ', $userid ]);
			# #if ($userid eq '#') { next; }
					
			# if (defined($userid)) {
				# #$AGI->exec('Espeak',"'Enter pin now.'");
				# #$AGI->stream_file('vm-saved');
				# my $pin = $self->get_speak_data({ agi => $AGI, text => 'Enter pin then pound.', timeout => 15000, chars => 10 });
				# #my $pin = $AGI->get_data('conf-getpin', 15000, 10);
				# $self->debuglog(['user entered this id/pin: ', $userid, $pin ]);
				# if (!defined($pin)) { next; }
				
				# $userobj->find({ criteria => { userid => $userid, pin => $pin }});
				# if (!$userobj->record_id()) { next; }
				# $self->debuglog(['looks like a legit user' ]);
		
				# #looks legit.
				# $loggedin_userid = $userid;
				# next;
			# }
		# }
		
		# #if we're here we fell out to this main menu by not entereing a 
		# if ($loggedin_userid) {
			# $self->customer_menu({agi=>$AGI, userobj=>$userobj} );
			# #came out here because user wants to log off.
			# $loggedin_userid = undef;
			# next;
		# } else {
			# $userobj->clear_record_id();
			# $self->newuser_process({agi=>$AGI, userobj=>$userobj } );
			# $loggedin_userid = $userobj->record_id(); #either has one or no, right?
			# $self->debuglog(['after newuser_process, userobj record id and loggedinuserid: ', $userobj->record_id(), $loggedin_userid ]);
			# next;
		# }
		
		# #probably won't get here?

		# $self->debuglog(['tiime to hang up.']);
		# #$AGI->stream_file($chopped, '0123');
		# $AGI->stream_file('vm-goodbye');
		# $AGI->hangup();
		# last;
		# # #'; is sort of ok first one.
	
	# }
	
	return "Fun Times!";
}

sub get_speak_data {
	my $self = shift;
	my $args = shift;
	my $AGI = $args->{agi};
	my $text = $args->{text};
	my $timeout = $args->{timeout};
	my $chars = $args->{chars};
	#my $userobj = $args->{userobj};

	#my $starttime = time();
	my $tts = 'festival';
	my $firstchar = undef;
	if ($tts eq 'festival') {
		$firstchar = $self->festival_speak({ agi=>$AGI, text => $text });
	} else {
		$firstchar = $AGI->exec('Espeak',"'$text',".ALLDIG);
	}
	$self->debuglog(['firstchar atm?', $firstchar, 'did we just speak this:', $text ]);
	my $user_selection = undef;
	if ($firstchar == 0)  { $firstchar = undef; } #no data entry at all during reading, treat as undef.
	if ($firstchar == -1) { $firstchar = undef; } #thats error/hangup or something. treat as undef.
	if ($firstchar) {
		#we will get ascii value, so minus 48 for what we want, and if it happened to be * it will be -6 so fix it :D . yes, this is cheesy. sorry.
		$firstchar -= 48;
		#my $fix = { '-6' => '*', '-13' => '#' };
		if ($firstchar == -6) { $firstchar = '*'; } elsif ($firstchar == -13) { $firstchar = '#'; }
		$user_selection = $firstchar; 
	}

	if ($user_selection eq '#') {
		$self->debuglog(['user bailed for firstchar: ']);
		if ($args->{baildicator}) { return $user_selection; }
		return undef;
	} #user chose to bail.

	#how many more chars?
	my $getmorechars = $chars - length($firstchar);
	if ($args->{morechars_requires_firstchar} && !length($firstchar)) {
		$getmorechars = 0;
	}
	
	#there may be additional characters. wait for up to 10 sec to get up to 2 more chars. (so max accesible entry # would be 999)
	$self->debuglog(['getmorechars: ', $getmorechars, 'firstchar now', $firstchar ]);
	if ($getmorechars) {
		my $morechars = $AGI->get_data('silence/1', $timeout, $getmorechars);
		$user_selection .= $morechars;
		$self->debuglog(['morechars: ', $morechars, ]);
	}
	if ($user_selection eq '') { $user_selection = undef; }
	$self->debuglog(['finished selection: ', $user_selection ]);
	
	return $user_selection;
}


sub customer_menu {
	my $self = shift;
	my $args = shift;
	my $AGI = $args->{agi};
	my $userobj = $args->{userobj};
	#my $client = $args->{rpcclient};

	my $acked = 0;
	my $logoff = 0;
	#my $possible_tx_fee = 0.0005;
	#while (!$acked) {
	#while (1) {
	#$AGI->exec('Espeak',"'Testing the reading back to you of a very long string and also with no options does pound cancel this shit or what?','#'");
	my $operator_rate = 0.0;

	my $moreinfo = "This system is running on an Amazon EC2 Small instance using Asterisk, Festival, Perl, My S Q L, and Bitcoin D.; SMS Services are provided by SMS Dragon. D I D services are provided by link 2 V O I P in Victoria BC and by I P Kall in Tacoma Washingon. BTC Address Q R Code display available by visiting C H W S dot C A slash B T C slash; then your account number. Follow your BTC Address link to view your BTC Address Q R Code.";
	
	my $useful_choices = {1=>1, 2=>1, 3=>1, 4=>1, 5=>1,9=>1,'#'=>1};
	while (!$logoff) {
		#play a menu.
		$self->debuglog(['customer menu loop']);
		my $menuchoice = undef;
		while (!$menuchoice) {
			$menuchoice ||= $self->festival_speak({agi=>$AGI, text => 'Customer Menu. Press 1 for your Balance, Press 2 to Send BTC, Press 3 for your BTC Address, Press 4 for your Address Book, Press 5 to wait for Bitcoin. Press 9 for more info. Press Pound to Log Off' });
			#$menuchoice ||= $AGI->exec('Espeak',"'Customer Menu. 1 for Balance. 2 to Send. 3 for BTC Address. 4 for Directory. 5 to wait for bitcoin. Pound to logoff',".ALLDIG);
			$menuchoice ||= $AGI->wait_for_digit(3000); #pause
		}
		$menuchoice -= 48;
		if ($menuchoice == -6) { $menuchoice = '*'; } elsif ($menuchoice == -13) { $menuchoice = '#'; }
		if (!$useful_choices->{$menuchoice}) {
			#no valid choice was made.
			next;
		}
		$self->debuglog(['useful customer menu choice: ', $menuchoice  ]);
		
		# #my $menuchoice = $self->get_speak_data({ agi => $AGI, text => 'Customer Menu. 1 for Balance. 2 to Send. 3 for BTC Address. 4 for Directory. 5 to wait for bitcoin. Pound to logoff', timeout => 10000, chars => 1, baildicator => 1, morechars_requires_firstchar => 1 });
		# my $menuchoice = $self->get_speak_data({ agi => $AGI, text => 'Fight', timeout => 10000, chars => 1, baildicator => 1, morechars_requires_firstchar => 1 });
		# #if (!defined($menuchoice)) {
			# #wait silently before looping again. dont fuck up over character codes (dumbass).
			# #$menuchoice ||= $AGI->wait_for_digit(5000);
		# #}
		
		# $self->debuglog(['customer menu loop: menu choice during the long prompt:', $menuchoice ]);
		# #$self->debuglog(['customer menu loop: menu choice after waiting for digit (silently):', $menuchoice ]);
		
		# $menuchoice -= 48; #cuz it will be an ascii code if its legit.

		#if ($menuchoice < 0 ) { next; } #thats not a proper response!!
		#if ($menuchoice !~ /^\d+$/ ) { 
		if ($menuchoice eq '*' || !defined($menuchoice)) {
			$self->debuglog(["thats not actually an option. why did i put this here?"]);
			next; 
		} #thats not a proper response!!
		if (defined($menuchoice) && $menuchoice eq 0) { 
			$self->debuglog(["$menuchoice eq 0, in fact. of course outside of a string menuchoice looks like:", $menuchoice ]);
			last; 
		} #wants to disconnect.
		if ($menuchoice eq 1) {
			#state balance!
			my $bal      = $self->get_user_balance({agi=>$AGI, userobj=>$userobj });
			my $unco_bal = $self->get_user_balance({agi=>$AGI, userobj=>$userobj, confirmations => 0 });
			#my $acked = $AGI->exec('Espeak',"'Your 6 times confirmed balance is',".ALLDIG);	
			my $acked = $self->festival_speak({ agi=>$AGI, text => 'Your 6 times confirmed balance is' });
			$acked ||= $AGI->say_alpha($bal, ALLDIG);
			$acked ||= $self->festival_speak({ agi=>$AGI, text => 'Your Un Confirmed balance is' });
			#$acked ||= $AGI->exec('Espeak',"'Your Un Confirmed balance is',".ALLDIG);	
			$acked ||= $AGI->say_alpha($unco_bal, ALLDIG);
			$self->debuglog(['should have spoke the balance of ', $bal, 'and unconfirmed:', $unco_bal ]);
			$acked ||= $AGI->wait_for_digit(1000); #2sec pause
		} elsif ($menuchoice eq 2) {

			#send btc.
			
			my $to_address = $self->addressbook_manager({agi=>$AGI, userobj=>$userobj, get_entry => 1 });
			if (!$to_address) {
				#fuck it.
				$self->debuglog(["hrm did not get an address to send to?"]);
				#$AGI->exec('Espeak',"'Could not determine recipient bitcoin address. Sorry please try again.',".ALLDIG);	
				$self->festival_speak({ agi=>$AGI, text => 'Could not determine recipient bitcoin address. Sorry please try again.' });
				#$AGI->stream_file('vm-sorry', ALLDIG);
				next; 
			}

			my $amount = $self->get_btc_amount({agi=>$AGI, userobj=>$userobj });
			if (!$amount) { 
				#fuck it.
				$self->debuglog(['hrm didnt get an amount we can use?']);
				#$AGI->exec('Espeak',"'Cannot proceed without an amount.',".ALLDIG);	
				$self->festival_speak({ agi=>$AGI, text => 'Cannot proceed without an amount.' });
				#$AGI->stream_file('vm-sorry', ALLDIG);
				next; 
			} 

			my $bal = $self->get_user_balance({agi=>$AGI, userobj=>$userobj });
			$self->debuglog(['amount requested to send: ', $amount, 'current balance of user (according to bitcoind anyway)', $bal ]);
			#my $operator_fee = $amount * $operator_rate;
			#if ($bal < ($amount+$possible_tx_fee)) {
			if ($bal < ($amount)) {
				#fuck it.
				#$self->debuglog(["hrm balance is too low? balance: $bal vs amount: $amount, possible tx fee: $possible_tx_fee"]);
				$self->debuglog(["hrm balance is too low? balance: $bal vs amount: $amount,"]);
				#$AGI->exec('Espeak',"'Sorry balance too low to send that amount.',".ALLDIG);	
				$self->festival_speak({ agi=>$AGI, text => 'Sorry balance too low to send that amount.' });
				#$AGI->stream_file('vm-sorry', ALLDIG);
				next; 
			}

			#$amount = sprintf('%0.8f', $amount); #formatting isssue?

			$self->debuglog(['send some bitcoins to:', $amount, $to_address ]);
			#should already have validated that address when it was added to the system, go ahead send btc lol.
				#should probably log the tx. but we dont really care about that yet.
			
			my $tx_id = undef;
			my $failed = 0;
			if ($to_address->{syscode}) {
				#woops we need the internal account name ;)
				my $checker = CaptchaQuest::BTCDataObj::BTCSysUser->new($self);
				$checker->find({criteria => {userid => $to_address->{syscode} }});
				if (!$checker->record_id()) { $failed = 1; } #this should not happen.
				#my $success = $self->move_btc({agi=>$AGI, userobj=>$userobj, to => $to_address->{syscode}, amount => $amount });
				my $success = $self->move_btc({agi=>$AGI, userobj=>$userobj, to => 'btcsysuser_' . $checker->record_id(), amount => $amount });
				$self->debuglog(['result?:', $success ]);
				if (!$success) { $failed = 1; }
			} elsif ($to_address->{btc_address}) {
				my $tx_id = $self->send_btc({agi=>$AGI, userobj=>$userobj, to => $to_address->{btc_address}, amount => $amount });
				#if i cared, i would attach this tx id (long str like: 860925e5dbad04481dce2212afc38113bb801d57547981899f6ad07b91de1b79 ) to this user in a ledger or something. or inspect it for fees charged. or something. fuck.
				$self->debuglog(['result?:', $tx_id ]);
				if (!$tx_id) { $failed = 1; }
			}

			if ($failed) {
				#fuck it.
				#$AGI->exec('Espeak',"'We are sorry. Something went wrong while talking to the bitcoin server. Please try again later.',".ALLDIG);
				$self->festival_speak({ agi=>$AGI, text => 'We are sorry. Something went wrong while talking to the bitcoin server. Please try again later.' });
				next;
			}
			
			my $bal = $self->get_user_balance({agi=>$AGI, userobj=>$userobj });
			my $acked = 0;
			#$acked ||= $AGI->exec('Espeak',"'Congratulations you have now sent',".ALLDIG);
			$acked ||= $self->festival_speak({ agi=>$AGI, text => 'Congratulations you have now sent' });
			$acked ||= $AGI->say_alpha($amount, ALLDIG);
			#$acked ||= $AGI->exec('Espeak',"'Bitcoins. Your new balance is',".ALLDIG);
			$acked ||= $self->festival_speak({ agi=>$AGI, text => 'Bitcoins. Your new balance is' });
			$acked ||= $AGI->say_alpha($bal, ALLDIG);
			if ($tx_id) {
				#$acked ||= $AGI->exec('Espeak',"'The transaction id was:',".ALLDIG);
				$acked ||= $self->festival_speak({ agi=>$AGI, text => 'The transaction id was:' });
				$acked ||= $AGI->say_phonetic($tx_id, ALLDIG);
			}
			#$acked ||= $AGI->exec('Espeak',"'Thank you for using our service.',".ALLDIG);
			$acked ||= $self->festival_speak({ agi=>$AGI, text => 'Thank you for using our service.' });
			next;
			
		} elsif ($menuchoice eq 3) {
			#say my btc address. this'll be fun! whee. loop until kicked out by digit press (b/c they might have to listen to it a few times to get it 
			my $addy = $userobj->val('btc_address'); #should this come from bitcoind?? probably. and if its different from the one on user record update that. anyway this should work for now.
			my @addy_chars = split(//,$addy);
			my $acked = 0;
			while (!$acked) {

				#$acked ||= $AGI->say_phonetic($addy, ALLDIG);
				#$acked ||= $AGI->exec('Espeak',"'Your Syscode number',".ALLDIG);
				$acked ||= $self->festival_speak({agi=>$AGI, text => 'Your Syscode number is' });
				$acked ||= $AGI->say_alpha(sprintf('%010u',$userobj->val('userid')), ALLDIG);
				#$acked ||= $AGI->stream_file('vm-num-i-have', ALLDIG); #my btc address?
				$acked ||= $AGI->wait_for_digit(500); #pause between them.
				#$acked ||= $AGI->exec('Espeak',"'Your Bitcoin address',".ALLDIG);
				
				$self->debuglog(['should be speaking this somehow: ', $addy, \@addy_chars ]);
				foreach my $speed ('slow','fast') {
					if ($speed eq 'slow') {
						$acked ||= $self->festival_speak({agi=>$AGI, text => 'Your Bitcoin address is: ' });
					} else {
						#$acked ||= $AGI->exec('Espeak',"'Your Bitcion address again',".ALLDIG);
						$acked ||= $self->festival_speak({agi=>$AGI, text => 'Your Bitcoin address again: ' });
					}
					$acked ||= $AGI->wait_for_digit(250); #pause between them.
					foreach my $char (@addy_chars) {
						if ($char !~ /\d/) {
							#indicate upper or lower case parts of btc address.
							if (lc($char) eq $char) {
								$acked ||= $AGI->stream_file('phoneapp/Lower_case', ALLDIG);
							} else {
								#$acked ||= $AGI->exec('Espeak',"'Capital',".ALLDIG);
								$acked ||= $AGI->stream_file('phoneapp/Capital', ALLDIG);
								#$acked ||= $AGI->stream_file('spy-zap', ALLDIG); #'capital'/'uppercase'
								
							}
						} else {
							#small delay for digits b/c of the time flow.
							$acked ||= $AGI->wait_for_digit(500); #pause between them.
						}
						if ($speed eq 'slow') {
							$acked ||= $AGI->say_phonetic($char, ALLDIG);
						} else {
							$acked ||= $AGI->say_alpha($char, ALLDIG);
						}
						if ($speed eq 'slow') {
							$acked ||= $AGI->wait_for_digit(1000); #pause between them.
						}
					}
				}

				#then after saying it like that, say it faster all in one go without the captials, just for quick review.
				#$acked ||= $AGI->say_alpha($addy, ALLDIG);
				$acked ||= $AGI->wait_for_digit(1000); #pause between them.
				
				$acked ||= $self->festival_speak({agi=>$AGI, text => 'Press any button to return to the customer menu' });
				#$acked ||= $AGI->stream_file('vm-press', ALLDIG); #'press any button to acknowledge your shit';
				#$acked ||= $AGI->exec('Espeak',"'any button',".ALLDIG);
				$acked ||= $AGI->wait_for_digit(3000);
				$self->debuglog(['here4', $acked ]);
			}
			$AGI->wait_for_digit(1000); #1sec pause
		} elsif ($menuchoice eq 4) {
			$self->addressbook_manager({agi=>$AGI, userobj=>$userobj });
			$self->debuglog(["just returned from addressbook manager."]);
		} elsif ($menuchoice eq 5) {
			$self->wait_for_btc({agi=>$AGI, userobj=>$userobj });
			$self->debuglog(["just returned from waiting."]);
		} elsif ($menuchoice eq 9) {
			my $acked ||= $self->festival_speak({agi=>$AGI, text => $moreinfo });
			$self->debuglog(["delivering more info."]);
		} elsif ($menuchoice eq '#') {
			$logoff = 1;
			$self->debuglog(["logoff ordered."]);
		}
		$self->debuglog(['customer menu loop 2, choice:', $menuchoice ]);
	}

	return 1;
}

sub send_btc {
	my $self = shift;
	my $args = shift;
	my $AGI = $args->{agi};
	my $userobj = $args->{userobj};
	my $to      = $args->{to};
	my $amount  = $args->{amount};

	my $rpcresult = $self->bitcoin_rpc({ rpc_call => { method  => 'sendfrom', params => [ 'btcsysuser_'.$userobj->record_id(), $to, $amount+0.0, 6 ] }, agi => $AGI }); #6 confirmations.
	return $rpcresult;
}

sub move_btc {
	my $self = shift;
	my $args = shift;
	my $AGI = $args->{agi};
	my $userobj = $args->{userobj};
	my $to      = $args->{to}; #must be an internal account name.
	my $amount  = $args->{amount};

	my $rpcresult = $self->bitcoin_rpc({ rpc_call => { method  => 'move', params => [ 'btcsysuser_'.$userobj->record_id(), $to, $amount+0.0, 6 ] }, agi => $AGI }); #6 confirmations.
	return $rpcresult;
}

sub wait_for_btc {
	my $self = shift;
	my $args = shift;
	my $AGI = $args->{agi};
	my $userobj = $args->{userobj};

	my $waiting = 1;

	#also I'm thinking it would be a pretty easy kludge to listen for user pressing ONE or something any time during this and we can just read off x number of recent transactions for shits and giggles.
	#as a quick hack to some kind of means to list recent tx.
	
	#my $newset_tx = $self->bitcoin_rpc({ rpc_call => { method  => 'listtransactions', params => [ 'btcsysuser_'.$userobj->record_id(), 1 ] }, agi => $AGI }); #6 confirmations.
	#my $timestamp = $most_recent_tx->{time};
	#my $last_timestamp   = time() - 10*60; #so lets say starting from 5 minutes ago. might be nice to be able to let user choose.
	my $last_timestamp   = time(); #probably should let user select how far back to look ... for now just show anything that comes in after NOW.
	#or maybe code a mode of this that lists a number of recent transactions instead of a live stream like this? hrm whatever!!
	my $newest_timestamp = undef;
	my $newest_mentioned = 1;
	my $exit = 0;
	my $checker = CaptchaQuest::BTCDataObj::BTCSysUser->new($self);
	
	#this is teh awesome. This is one of the whole points of this system :) 
	#For merchant and customer to both be on their phones at the same time,
	#for merchant to hear live the completed incoming transaction and complete the sale!
	my $mentionables = {'move'=>1,'receive'=>1};
	while ($waiting) {

		#$exit ||= $AGI->exec('Espeak',"'Checking for recent transactions',".ALLDIG);
		$exit ||= $self->festival_speak({agi=>$AGI, text => 'Checking for recent transactions' });
		$exit ||= $AGI->wait_for_digit(500); #pause

		my $newest_tx = $self->bitcoin_rpc({ rpc_call => { method  => 'listtransactions', params => [ 'btcsysuser_'.$userobj->record_id(), 1 ] }, agi => $AGI });
		$newest_timestamp = $newest_tx->[0]->{time};
		
		#did we get a new one?
		if ($newest_timestamp > $last_timestamp) {
			$self->debuglog(['i believe this is bigger than that, so i am gonna tell you about it', $newest_timestamp, $last_timestamp ]);
			$last_timestamp = $newest_timestamp;
			$newest_mentioned = 0;
		}
		
		#the idea here I'm thinking, is wait for any new "move" tx to come in to our account. these would be from other users of the system and should insta-clear balances on those (automatically, bitcoind will show the new balance even with conf=6 right away as long as underlying incoming btc was conf=6 ... i think.. HAHA)
		#if (!$newest_mentioned && $newest_tx && $newest_tx->[0] && ($newest_tx->[0]->{category} eq 'move') && ($newest_tx->[0]->{amount} > 0) ) {
		#if (!$newest_mentioned && $newest_tx && $newest_tx->[0] && ($newest_tx->[0]->{amount} > 0.0) ) {
		if (!$newest_mentioned && $newest_tx && $newest_tx->[0] && ($mentionables->{$newest_tx->[0]->{category}}) && ($newest_tx->[0]->{amount} > 0) ) {
			if (($newest_tx->[0]->{category} eq 'move')) {
				(my $newest_tx_from = $newest_tx->[0]->{otheraccount}) =~ s|^btcsysuser_(\d+)$|$1|;
				$self->debuglog(['s.b. telling user about this move tx from this userid:', $newest_tx->[0], $newest_tx_from ]);
				$checker->load($newest_tx_from);

				#$exit ||= $AGI->exec('Espeak',"'Most recently received',".ALLDIG);
				#$exit ||= $AGI->exec('Espeak',"'You have just received',".ALLDIG);
				$exit ||= $self->festival_speak({agi=>$AGI, text => 'You have just received' });
				$exit ||= $AGI->say_alpha($newest_tx->[0]->{amount}, ALLDIG);
				#$exit ||= $AGI->exec('Espeak',"'Bitcoins from syscode ',".ALLDIG);
				$exit ||= $self->festival_speak({agi=>$AGI, text => 'Bitcoins from syscode' });
				$exit ||= $AGI->say_alpha(sprintf('%010u',$checker->val('userid')), ALLDIG);
				my $bal = $self->get_user_balance({agi=>$AGI, userobj=>$userobj });
				#$exit ||= $AGI->exec('Espeak',"'Your balance is currently ',".ALLDIG);
				$exit ||= $self->festival_speak({agi=>$AGI, text => 'Your balance is currently ' });
				$exit ||= $AGI->say_alpha($bal, ALLDIG);
			} elsif (($newest_tx->[0]->{category} eq 'receive')) {
				#(my $newest_tx_from = $newest_tx->[0]->{otheraccount}) =~ s|^btcsysuser_(\d+)$|$1|;
				my $tx_id = $newest_tx->[0]->{txid};
				my $read_as .= 'Transaction ID starting ' . join(', ', split(//,substr(uc($tx_id), 0, 3))) . '; and ending ' . join(', ', split(//,substr(uc($tx_id), -3))) .', ;';
				
				$self->debuglog(['s.b. telling user about this unconfirmed receive tx:', $newest_tx->[0], $read_as]);
				#$checker->load($newest_tx_from);

				#$exit ||= $AGI->exec('Espeak',"'Most recently received',".ALLDIG);
				#$exit ||= $AGI->exec('Espeak',"'You have just received',".ALLDIG);
				$exit ||= $self->festival_speak({agi=>$AGI, text => 'You have just received' });
				$exit ||= $AGI->say_alpha($newest_tx->[0]->{amount}, ALLDIG);
				#$exit ||= $AGI->exec('Espeak',"'Bitcoins from $read_as',".ALLDIG);
				$exit ||= $self->festival_speak({agi=>$AGI, text => "Bitcoins from $read_as" });
				$exit ||= $AGI->wait_for_digit(500); #pause
				my $unco_bal = $self->get_user_balance({agi=>$AGI, userobj=>$userobj, confirmations => 0 });
				#$exit ||= $AGI->exec('Espeak',"'Your Un Confirmed balance is currently ',".ALLDIG);
				$exit ||= $self->festival_speak({agi=>$AGI, text => "Your Un Confirmed balance is currently" });
				$exit ||= $AGI->say_alpha($unco_bal, ALLDIG);
			}
			$newest_mentioned = 1;
		} else {
			#$exit ||= $AGI->wait_for_digit(5000); #pause
			#$exit ||= $AGI->exec('Espeak',"'No recent transactions.',".ALLDIG);
			$exit ||= $self->festival_speak({agi=>$AGI, text => "No recent transactions." });
		}
		
		
		#and then a pause between checks regardless.
		$exit ||= $AGI->wait_for_digit(5000); #pause
		
		if ($exit) { 
			$self->debuglog(['i believe its time to exit because:', $exit ]);
			$waiting = 0;
			last; 
		}
	}
	
}

sub addressbook_manager {
	my $self = shift;
	my $args = shift;
	my $AGI = $args->{agi};
	my $userobj = $args->{userobj};
	my $get_entry = $args->{get_entry};

	#i'm scared!!!
	my $addrbook = CaptchaQuest::BTCDataObj::BTCSysAddressbook->new($self);
	my $junkpile = CaptchaQuest::BTCDataObj::BTCSysSMSJunk->new($self);
	my $userlookup = CaptchaQuest::BTCDataObj::BTCSysUser->new($self); 
	
	my $address = undef;
	my $useful_choices = {1=>1, 2=>1, 3=>1};
	my $addressbooking = 1;
	while ($addressbooking) {
		my $choice = undef;
		#while (!defined($choice)) {
		while (!$choice) {
			# 1 to add a new syscode entry
			# 2 to add a btc addresss 
			# 3 to list existing entries
			#anything else to bail.
			#$choice = $AGI->get_data('queue-holdtime', 8000, 1);
			#$choice ||= $AGI->exec('Espeak',"'Payee Addressbook. Press 1 to Add a Payee by SysCode. Press 2 to Add a Payee by SMS message. Press 3 to list existing entries.',".ALLDIG);
			my $prompt = 'Press 1 to Add a Recipient by SysCode. Press 2 to Add a Recipient by SMS message. Press 3 to list existing entries.';
			if ($get_entry) {
				$prompt = 'Select a recipient from your Address Book. ' . $prompt;
			} else {
				$prompt = 'Recipient Address Book. ' . $prompt;
			}
			#$choice ||= $self->festival_speak({agi=>$AGI, text => 'Recipient Address Book. Press 1 to Add a Recipient by SysCode. Press 2 to Add a Recipient by SMS message. Press 3 to list existing entries.' });
			$choice ||= $self->festival_speak({agi=>$AGI, text => $prompt });
			$choice ||= $AGI->wait_for_digit(3000); #pause
			#if ($choice) { $choice -= 48; if ($choice 

		}
		$choice -= 48;
		if (!$useful_choices->{$choice}) {
			#no valid choice was made.
			return undef;
		}
		$self->debuglog(['useful addressbook menu 1 choice: ', $choice  ]);

		if ($choice eq 1) {
			#add new one (by syscode)
			my $legit_newentry = 0;
			my $checker = CaptchaQuest::BTCDataObj::BTCSysUser->new($self);
			while (!$legit_newentry) {
				#my $syscode = $AGI->get_data('vm-INBOX', 15000, 10);
				#$AGI->exec('Espeak',"'Enter payee syscode.'");
				$self->festival_speak({agi=>$AGI, text => 'Enter recipient syscode.' });
				my $syscode = $AGI->get_data('silence/1', 15000, 10);
				if (!defined($syscode))    { last; } #no input or user bails with poundsign.
				$checker->find({criteria => {userid => $syscode }});
				if (!$checker->record_id()) { next;	} #failed to match a real user? try again?

				$self->debuglog(['addressbook new entry syscode: ', $syscode  ]);
				#press 1 to confirm it any time during this playback loop
				my $acked = 0;
				while (!$acked) {
					#$acked ||= $AGI->exec('Espeak',"'You entered:',".ALLDIG);
					$acked ||= $self->festival_speak({agi=>$AGI, text => 'You entered:' });
					#$acked ||= $AGI->stream_file('vm-num-i-have', ALLDIG); #confirm to use this one:
					#probably read back first+last bits of btc addy as well.
					$acked ||= $AGI->wait_for_digit(500);
					$acked ||= $AGI->say_alpha($syscode, ALLDIG);
					$acked ||= $AGI->wait_for_digit(1000);
					#$acked ||= $AGI->exec('Espeak',"'Press 1 to confirm new address book entry or any other digit to abort.',".ALLDIG);
					$acked ||= $self->festival_speak({agi=>$AGI, text => 'Press 1 to confirm new address book entry or any other digit to abort.' });
					$acked ||= $AGI->wait_for_digit(3000);
				}
				#if they pressed something other than 1 ...
				if (($acked - 48) != 1) {
					next;
				}
				
				#check for addressbook dupes.
				my $dupe_rec = $addrbook->get_search_results({ restrict => { userid => $userobj->val('userid'), syscode => $syscode } })->{records_simple}->[0];
				if (!$dupe_rec) {
					#find highest display order and add 1 to it.
					my $disp_ord = 1;
					my $max_disp_rec = $addrbook->get_search_results({ restrict => { userid => $userobj->val('userid') }, user_sort => { parameter_name => 'display_order', dir => 'DESC' } })->{records_simple}->[0];
					if ($max_disp_rec) {
						$disp_ord = $max_disp_rec->{display_order} + 1;
					}
					my $entry = {
						userid        => $userobj->val('userid'),
						syscode       => $syscode,
						display_order => $disp_ord,
					};
					#ok so here we are they confirmed the new addressbook entry we should save it.
					$addrbook->newrec($entry)->save();
					$self->debuglog(['just saved new addressbook entry:', $entry ]);
				} else {
					#$AGI->exec('Espeak',"'L O L You already had that one. Thats ok.',".ALLDIG);
					$self->festival_speak({agi=>$AGI, text => 'L O L You already had that one. Thats ok.' });
					$self->debuglog(['didnt bother to save duplicate entry in adressbook. just laughed about it.']);
				}
					
				if ($get_entry) {
					#so is this then entry they want to USE?
					my $confirmed = 0;
					while (!$confirmed) {
						#$confirmed ||= $AGI->exec('Espeak',"'You have selected the recipient: ',".ALLDIG);
						$confirmed ||= $self->festival_speak({agi=>$AGI, text => 'You have selected the recipient: ' });
						#$confirmed ||= $AGI->stream_file('vm-press', ALLDIG); #confirm to use this one:
						#probably read back first+last bits of btc addy as well.
						$confirmed ||= $AGI->wait_for_digit(500);
						$confirmed ||= $AGI->say_alpha($syscode, ALLDIG);
						#$confirmed ||= $AGI->exec('Espeak',"'To recieve bitcoins. Press 1 to confirm this recipient.',".ALLDIG);
						$confirmed ||= $self->festival_speak({agi=>$AGI, text => 'to recieve bitcoins. Press 1 to confirm this recipient.' });
						$confirmed ||= $AGI->wait_for_digit(8000);
					}
					#if they pressed something other than 1 ...
					if (($confirmed - 48) != 1) {
						next;
					}
					#hrm. we're here. must be the one they want to use!! (send back btc addy of looked up system user)
					#return $checker->val('btc_address');
					return { 
						syscode     => $checker->val('userid'), #instaclear baby!
						btc_address => $checker->val('btc_address'),
					};
					
				}
				$legit_newentry = 1;
			}
		} elsif ($choice eq 2) {
			#btc address entry nyi.
			#$AGI->stream_file('vm-sorry');
			#my $acked = $AGI->exec('Espeak',"'Skip this message by pressing pound. BTC Addresses can be sent via SMS to phone number:,".ALLDIG);
			my $acked = $self->festival_speak({agi=>$AGI, text => 'Skip this message by pressing pound. BTC Addresses can be sent via SMS to phone number:' });
			$acked ||= $AGI->say_alpha($self->config('smsdragon_mobilenum'));

			## what number will they be sending sms from?
			my $cur_receive_sms_from = $userobj->val('receive_sms_from');
			#if one is on file, confirm it. (accept it or delete it from the system.)
			my $bail = 0;
			if ($cur_receive_sms_from) {
				my $reviewing = 1;
				while ($reviewing) {
					my $confirmed = 0;
					while (!$confirmed) {
						#$confirmed ||= $AGI->exec('Espeak',"'Currently you are set to receive BTC addresses from SMS phone number:,".ALLDIG);
						$confirmed ||= $self->festival_speak({agi=>$AGI, text => 'Currently you are set to receive BTC addresses from SMS phone number:' });
						$confirmed ||= $AGI->say_alpha($cur_receive_sms_from);
						#$confirmed ||= $AGI->exec('Espeak',"'If this is correct press 1 to continue. If this is an error press 2 to delete this SMS number.',".ALLDIG);
						$confirmed ||= $self->festival_speak({agi=>$AGI, text => 'If this is correct press 1 to continue. If this is an error press 2 to delete this SMS number.' });
						$confirmed ||= $AGI->wait_for_digit(8000);
					}
					if (($confirmed - 48) == 1) { $reviewing = 0; } #chosen.
					if (($confirmed - 48) == -13) { $reviewing = 0; $bail = 1; }
					#user doesnt want to use this number.
					if (($confirmed - 48) == 2) { 
						$reviewing = 0;
						$userobj->val('receive_sms_from' => undef )->save();
						$cur_receive_sms_from = undef;
					}
				}				
			}
			if ($bail) { next; }
			
			#if not, ask for a new one to store on file.
			if (!$cur_receive_sms_from) {
				#get one or bail from this whole process.
				my $inputting = 1;
				while ($inputting) {
					$cur_receive_sms_from = $self->get_speak_data({ agi => $AGI, text => 'Enter the number from which we will receive the SMS message for you. Followed by pound.', timeout => 15000, chars => 20 });
					if (!$cur_receive_sms_from) { 
						#shitty choice. we're done obviously.
						$bail = 1;
						last;
					}

					#got one, confirm it or bail?
					my $confirmed = 0;
					while (!$confirmed) {
						#$confirmed ||= $AGI->exec('Espeak',"'You have selected:,".ALLDIG);
						$confirmed ||= $self->festival_speak({agi=>$AGI, text => 'You have selected:' });
						$confirmed ||= $AGI->say_alpha($cur_receive_sms_from);
						#$confirmed ||= $AGI->exec('Espeak',"'If this is correct press 1 to continue. If this is an error press 2 to re-enter the SMS number.',".ALLDIG);
						$confirmed ||= $self->festival_speak({agi=>$AGI, text => 'If this is correct press 1 to continue. If this is an error press 2 to re-enter the SMS number.' });
						$confirmed ||= $AGI->wait_for_digit(8000);
					}
					if (($confirmed - 48) == -13) { $inputting = 0; $bail = 1; }
					if (($confirmed - 48) == 1) { 
						#chosen. save it.
						$inputting = 0;
						$userobj->val('receive_sms_from' => $cur_receive_sms_from )->save();
					} 
					#user doesnt want to use this number.
					if (($confirmed - 48) == 2) { 
						#$inputting = 0; 
						next; #try again?
					}
					
				}
			}
			if ($bail) { next; }
			if (!$cur_receive_sms_from) { next; } #cuz we can't effectively be here without one !!
			
			#then check for some btc address info from the rss feed.
			#so we can get a list of rss entries from the phone num on this user' account.
			my $sms_messages = $self->get_sms_messages({ from_number => $cur_receive_sms_from });
			#and any ones that are 34 chars long, we can give a shit about.
			my $possible_good_sms =  [ grep { (length($_->{btc_address}) == 34) } @$sms_messages ]; #only ones with 34 character btc addresses.
			#my $already_known = {}; #tracker.
			#and for any of those, we can see if we have them already in user' address book 
			my $entries  = $addrbook->get_search_results({ restrict => { userid => $userobj->val('userid') }, user_sort => {parameter_name => 'display_order'} })->{records_simple};
			#or in the junk rss data table.
			my $junky    = $junkpile->get_search_results({ restrict => { userid => $userobj->val('userid') }, })->{records_simple};
			my $fresh_candidates = [];
			my $fresh_junk       = [];
			my $highest_dispord = 0;
			foreach my $candidate (@$possible_good_sms) {
				my $old = 0;
				foreach my $addrbook_entry (@$entries) {
					if (!$highest_dispord) { $highest_dispord = $addrbook_entry->{display_order}; } #take note of that too. first one we see should be the highest anyway.
					if ($addrbook_entry->{btc_address} eq $candidate->{btc_address}) { $old = 1; } #already have this in our book.
				}
				foreach my $junker (@$junky) {
					if ($junker->{btc_address} eq $candidate->{btc_address}) { $old = 1; } #already junked before. (34 chars of fail?)
				}
				if (!$old) {
					# #probably check it for goodnicity here and if it fails, add it to the junk pile!
					my $validity_check = $self->bitcoin_rpc({ rpc_call => { method  => 'validateaddress', params => [ $candidate->{btc_address} ] } });
					if (!$validity_check) {
						#$AGI->exec('Espeak',"'We are sorry. Something went terribly wrong while talking to the bitcoin server.',".ALLDIG);
						$self->festival_speak({agi=>$AGI, text => 'We are sorry. Something went wrong while talking to the bitcoin server.' });
						next;
					} elsif ($validity_check->{isvalid}) {
						push(@$fresh_candidates, $candidate);
					} else {
						#junk that shit.
						push(@$fresh_junk, $candidate);
						$junkpile->newrec({ btc_address => $candidate->{btc_address}, userid => $userobj->val('userid') })->save();
					}					
				}
			}
			
			#and so for all the ones that are not in the user' address book already (or junk), we will end up with a list.
			#we'll go over that list
			#we _maybe_ will later implement telling them about fresh junk but IMO just fucking send the info correctly in the first place :)
			my $added = 0;
			foreach my $candidate (@$fresh_candidates) {
				$highest_dispord++;
				my $btc_address = $candidate->{btc_address};
				my $entry = {
					userid        => $userobj->val('userid'),
					display_order => $highest_dispord,
					btc_address   => $btc_address,
				};
				#ok so here we are they confirmed the new addressbook entry we should save it.
				$addrbook->newrec($entry)->save();

				my $read_as .= 'BTC address starting ' . join(', ', split(//,substr(uc($btc_address), 0, 3))) . '; and ending ' . join(', ', split(//,substr(uc($btc_address), -3)))  .', ;';
				#my $acked = $AGI->exec('Espeak',"'Added a new $read_as to your address book',".ALLDIG);
				my $acked = $self->festival_speak({agi=>$AGI, text => "Added a new $read_as to your address book" });
				$acked ||= $AGI->wait_for_digit(1000); #just a brief pause if they didnt press a button during readout.

				#each of them we need to mention it. 
				#and add it to their address book.
				$added++;
			}
			#after completing this, jump back out to addressbook menu
			if ($added) {
				#$AGI->exec('Espeak',"'You have completed adding $added new entries you your address book via sms text message. Pretty damn cool if you ask me.',".ALLDIG);
				$self->festival_speak({agi=>$AGI, text => "You have completed adding $added new entries you your address book via sms text message. Pretty damn cool if you ask me." });
			} else {
				#$AGI->exec('Espeak',"'We were unable to find any new BTC address entries from the selected SMS number at this time. If you are expecting to receive BTC address information please check the validity of any sent data as well as the mobile number you are sending from and try your request again. Please note that the SMS message you send must contain only the 34 character bitcoin address and ensuring correct capitalization of each letter.',".ALLDIG);
				$self->festival_speak({agi=>$AGI, text => "We were unable to find any new BTC address entries from the selected SMS number at this time. If you are expecting to receive BTC address information please check the validity of any sent data as well as the mobile number you are sending from and try your request again. Please note that the SMS message you send must contain only the 34 character bitcoin address and ensuring correct capitalization of each letter." });
			}
			next;
				
			#my $checker = CaptchaQuest::BTCDataObj::BTCSysUser->new($self);
			
		} elsif ($choice eq 3) {
			#list existing entries and prompt for a selection.
			my $entries = $addrbook->get_search_results({ restrict => { userid => $userobj->val('userid') }, user_sort => {parameter_name => 'display_order'} })->{records_simple};
			$self->debuglog(['probably would want to tell user about all these and then ask for a choice:', $entries ]);
			my $entry_count = scalar(@$entries);
			my $c = 0;
			my $user_selection = undef;
			my $bail = 0;
			my $btc_address = undef;

			if (!$entry_count) {
				#$AGI->exec('Espeak',"No address book entries.'");
				$self->festival_speak({agi=>$AGI, text => "No address book entries." });
				return undef;
			}

			while (!$user_selection) {
				#note: might want to capture any char typed during the prompt as a firstchar ... right now there is sort of a bug in that user might start typing the entry # during this prompt but before the list starts reading and so then the # keypress is in the loop and causes no item to be selected!
				if ($get_entry) {
					#$AGI->exec('Espeak',"'$entry_count adressbook entries. Pick one and then press pound.'");
					$self->festival_speak({agi=>$AGI, text => "$entry_count adressbook entries. Pick one and then press pound." });
				} else {
					#$AGI->exec('Espeak',"'$entry_count adressbook entries. Press pound to stop listing.'");
					$self->festival_speak({agi=>$AGI, text => "$entry_count adressbook entries. Press pound to stop listing." });
				}
				foreach (@$entries) {
					if (!$_->{read_as}) {
						my $read_as = "Entry " . $_->{display_order} . ' ';
						if ($_->{syscode}) { $read_as .= 'syscode ' . join(' ', split(//,$_->{syscode})) . '; '; }
						if ($_->{btc_address}) {
							$btc_address = $_->{btc_address};
						} else {
							#lookup btc address info
							$userlookup->find({ criteria => { userid => $_->{syscode} }});
							if ($userlookup->record_id()) {
								$btc_address = $userlookup->val('btc_address');
							}
						}
						if (!$btc_address) { die "fatal no $btc_address (to be in this spot without one should be fatal)  error;" }
						$read_as .= 'BTC address starting ' . join(', ', split(//,substr(uc($btc_address), 0, 3))) . '; and ending ' . join(', ', split(//,substr(uc($btc_address), -3))) .', ;';
						$_->{read_as} = $read_as;
					}
					#something that reads them off and accepts somehow lets them select one.
					$user_selection = $self->get_speak_data({ agi => $AGI, text => $_->{read_as}, timeout => 10000, chars => 3, baildicator => 1, morechars_requires_firstchar => 1 });
					if ($user_selection eq '#') { $bail = 1; } #pressed as first char.
					if ($user_selection) { last; }
					#die "this is fucked there is no bail atm";

					# my $firstchar = $AGI->exec('Espeak',"'$_->{read_as}',".ALLDIG);
					# $self->debuglog(['firstchar atm?', $firstchar, 'did we just speak this:', $_->{read_as} ]);
					# if ($firstchar) { 
						# #we will get ascii value, so minus 48 for what we want, and if it happened to be * it will be -6 so fix it :D . yes, this is cheesy. sorry.
						# $firstchar -= 48;
						# #my $fix = { '-6' => '*', '-13' => '#' };
						# if ($firstchar == -6) { $firstchar = '*'; } elsif ($firstchar == -13) { $firstchar = '#'; }
						# $user_selection = $firstchar; 
					
						# if ($user_selection eq '#') {
							# $user_selection = undef;
							# $bail = 1;
							# last; 
						# } #user chose to bail.
						
						# #there may be additional characters. wait for up to 10 sec to get up to 2 more chars. (so max accesible entry # would be 999)
						# my $morechars = $AGI->get_data('silence/1', 10000, 2);
						# $user_selection .= $morechars;
						# $self->debuglog(['morechars and finished selection: ', $morechars, $user_selection ]);
						# last;
					# }

				}
				
				#if we're here without a user selection we should be trying the list over from the beginning.
				if ($bail) { last; } #unless we're ordered to bail of course.
			}
			
			if ($get_entry && !$bail) { 
			
				#if we didnt choose one just return undef.
				if (!$user_selection) { return undef; }

				#$self->debuglog(['here with user selection trying to find the entry by display order.morechars and finished selection: ', $morechars, $user_selection ]);
				my $selected_entry = undef;
				foreach (@$entries) { 
					if ($_->{display_order} eq $user_selection) {
						$selected_entry = $_;
					}
				}
				if (!$selected_entry) { 
					#$AGI->exec('Espeak',"'Sorry that entry is invalid.'");
					$self->festival_speak({agi=>$AGI, text => "Sorry that entry is invalid." });
					return undef; 
				} #bad choice ??

				#confirm selection?
				my $confirmed = 0;
				while (!$confirmed) {
					#$confirmed ||= $AGI->exec('Espeak',"'You have selected $selected_entry->{read_as}',".ALLDIG);
					$confirmed ||= $self->festival_speak({agi=>$AGI, text => "You have selected $selected_entry->{read_as}" });
					$self->debuglog(['selected confirmation entry read as: ', $selected_entry->{read_as} ]);
					#$confirmed ||= $AGI->exec('Espeak',"' To recieve bitcoins. Press 1 to confirm this recipient.',".ALLDIG);
					$confirmed ||= $self->festival_speak({agi=>$AGI, text => "to recieve bitcoins. Press 1 to confirm this recipient." });
					$confirmed ||= $AGI->wait_for_digit(8000);
				}
				#if they pressed something other than 1 ... then they are pissing me off.
				if (($confirmed - 48) != 1) {
					return undef;
				}
				#hrm. we're here. must be the one they want to use!! (send back btc addy of looked up system user)

				return $selected_entry;
				# { 
					# syscode     => $checker->val('userid'), #instaclear baby!
					# btc_address => $btc_address,
				# };

				#return $btc_address;
				
			}
		}
	}

	return undef;
}
# sub check_balance {

	# my $min = $args->{min};
	# #for now i just want to see if balance is >= $
# }

sub get_btc_amount {
	my $self = shift;
	my $args = shift;
	my $AGI = $args->{agi};
	my $userobj = $args->{userobj};

	my $amount = undef;
	my $acked = 0;
	my $bail = 0;
	#my $min_amount = 0.001; #experimenting to find min amounts with no fees. .. or anthing that reliably skips the JSON rpc error!!
	my $min_amount = 0.0; #but need to just figure out a way later to hack bitcoind to be able to tell us how much tx fee is going to be and let THE USER make a decision about it.
	
	#collect digits from the user
	while (!$amount) {
		#my $firstchar = $AGI->exec('Espeak',"'Amount to send? Use star for dot.',".ALLDIG);	
		my $firstchar = $self->festival_speak({agi=>$AGI, text => "Amount to send? Use star for decimal." });
		my $prepend = undef;
		if ($firstchar) { $firstchar -= 48; $prepend = ($firstchar == -6) ? '*' : $firstchar; } #star becomes minus 6. fix it.
		$self->debuglog(['user entered firchar during prompt: ', $firstchar ]);
		#$amount = $AGI->get_data('vm-enter-num-to-call', 15000, 12); #999.99999999 max
		$amount = $prepend . $AGI->get_data('silence/1', 15000, 12); #999.99999999 max
		$amount =~ s|\*|\.|;
		if (!(($amount+0) > 0)) {
			last; #bail?
		}
		if ($amount < $min_amount) {
			#my $acked = $AGI->exec('Espeak',"'Amount must be at least $min_amount . Please try again.',".ALLDIG);	
			my $acked = $self->festival_speak({agi=>$AGI, text => "Amount must be at least $min_amount . Please try again." });

			$amount = undef;
			next;
		}
		#$AGI->stream_file('conf-thereare', ALLDIG); #'you entered:';
		$self->debuglog(['user entered this amount: ', $amount ]);
		#repeat it back to them.
		while (!$acked) {
			#$AGI->exec('Espeak',"'You entered'");
			$self->festival_speak({agi=>$AGI, text => "You entered" });
			$AGI->say_alpha($amount);
			#my $choice = $AGI->exec('Espeak',"'Press 1 if satisfied. 2 to correct. 3 to abort',".ALLDIG);
			my $choice = $self->festival_speak({agi=>$AGI, text => "If this is correct press 1 to continue. If this is an error press 2 to make a correction. If you wish to abort this transaction press 3." });
			$choice ||= $AGI->wait_for_digit(5000);
			if (!$choice) { 
				#didnt press anything during espeak, ask to confirm again
				next;
			} else {
				#got ascii code of choice.
				$choice -= 48; 
			}
			$self->debuglog(['user choices: (1=use it, 2=must correct, other=bail', $choice  ]);
			#if ($choice == 0) { $choice = undef; }
			#my $choice = $AGI->get_data('dir-pls-enter', 8000, 1);
			if ($choice == 1) {
				$acked = 1;
			} elsif ($choice == 2) {
				#unhappy about it .. try again.
				$amount = 0;
				last;
			} else {
				#just bail.
				#note we cannot really use pound to bail here .. just any other digit than 1 or 2.
				$bail = 1;
				last;
			}
		}
		if ($bail) { last; }
	}
	return $amount;
}

sub get_user_balance {
	my $self = shift;
	my $args = shift;
	my $AGI = $args->{agi};
	my $userobj = $args->{userobj};
	my $confirmations = $args->{confirmations};
	if (!defined($confirmations)) { $confirmations = 6; }

	my $rpcresult = $self->bitcoin_rpc({ rpc_call => { method  => 'getbalance', params => [ 'btcsysuser_'.$userobj->record_id(), $confirmations ] }, agi => $AGI }); #6 confirmations by default
	return $rpcresult;
}

sub bitcoin_rpc {
	my $self = shift;
	my $args = shift;
	
	my $obj = $args->{rpc_call};
	my $AGI = $args->{agi};
	
	my $client = $self->{rpcclient};
	my $uri = 'http://localhost:8332/';
	if (!$client) {
		$client = JSON::RPC::Client->new();
		$client->ua()->timeout(60);
		$client->ua->credentials('localhost:8332', 'jsonrpc', 'manchUl4' => 'guyb4tr0sS' ); #those are shitty. put better onese. asshole. stop bitcoind first.
		$self->{rpcclient} = $client;
	}
	
	$self->debuglog(['trying to talk to bitcoind with this:', $obj ]);
	#stpid JSONencoder/perl/typecast/bitcoind hax???
		#derp i cant seem to make it work without this.
	if ($obj->{method} eq 'sendfrom') { $obj->{params}->[2] += 0.0; } #uh yeah that .. worked. wtf dunno why all the other += 0.0 was not working.
	if ($obj->{method} eq 'move')     { $obj->{params}->[2] += 0.0; } #uh yeah that .. worked. wtf dunno why all the other += 0.0 was not working.

	my $rpcresult = undef;
	my $res = undef;
	my $tries = 0;
	while (!$res) {
		$tries++;
		if ($tries >= 3) { last; } #too much. this func should probably be rewrote as well.
		
		#debug
		my $should_have_sent = $client->json()->encode($obj);
		$self->debuglog(['we plan to send this', $should_have_sent ]);
		#die "wait";
		#dbueg
		$res =$client->call( $uri, $obj );
		
		#debug
		# my $should_have_sent = $client->json()->encode($obj);
		# $self->debuglog(['we believe we sent', $should_have_sent ]);
		#dbueg
		
		if ($res){
			if ($res->is_error) { 
				#'sorry we could not communicate with bitcoin server please try again soon'
				$self->debuglog(['some kind of error talking with bitcoind, should take back to top of loop', $res->error_message ]);
				#$AGI && $AGI->stream_file('conf-muted');
				#print "Error : ", $res->error_message; 
				last;
			} else { 
				$rpcresult = $res->result();
				$self->debuglog(['some kind of successful result?', $rpcresult ]);
			}
		} else {
			#umm .. thanks shitty JSON rpc implemention in bitciond and/or perl module ... . because of this we gonna hit it a second time and get some real info?
			$self->debuglog(['no or bad response from bitcoind probably will try again?', $client->status_line ]);
			$res = $client->_post($uri, $obj);
			if ($res) {
				my $should_have_sent = $client->json()->encode($obj);
				$self->debuglog(['we sent this', $should_have_sent, 'and got back badness?:', $res->decoded_content() ]);
				last;
			}
			
			#$AGI && $AGI->stream_file('vm-sorry');
			#sleep(10); #wait a sec before trying again.
		}	
	}
	return $rpcresult;
}

	#my $path = '/usr/share/asterisk/sounds/en/';
	#my @list = glob($path.'*.gsm');
	# my $lol = 1;
	# while (1) {
		# $self->debuglog("$lol lulz");
		# $AGI->say_number($lol);
		# #my $userdata = $AGI->get_data('demo-enterkeywords', 15000, 5);
		# #$self->debuglog(['got this: ', $userdata ]);
		# #'agent-pass' is good for password.
		# #'privacy-prompt; is sort of ok first one.
		# #'spy-local' various short strings
		
		# my $skip = 'privacy-incorrect';
		# my $arrived = 0;
		# my $count = 0;
		# foreach my $file (@list) {
			# $count++;
			# (my $chopped = $file) =~ s|.*\/(.*)\.gsm|$1|;
			# #if ($count <= $skip) { next; }
			# if ($skip && !$arrived && ($chopped ne $skip)) { 
				# next; 
			# } else {
				# $arrived = 1;
			# }
				
			# my $random = int(rand(50));
			# $self->debuglog(["now playing: $chopped - $random"]);
			# $AGI->stream_file($chopped, '0123');
			# $AGI->say_alpha($random);
			# #print $chopped . "\n";
		# }
		# #$AGI->say_alpha("b1ean".$lol);
		# #$AGI->say_phonetic("b1ean".$lol);
		# $lol++;
		
		# if ($lol > 2) {
			# $AGI->hangup();
			# last;
		# }
		# sleep(1);
	# }
	
	
sub newuser_process {
	my $self = shift;
	my $args = shift;
	my $AGI = $args->{agi};
	my $userobj = $args->{userobj};
	#my $client = $args->{rpcclient};

	#say choose a pin number
	#$AGI->exec('Espeak',"\"New user enter a new pin then press pound.\"");
	$self->festival_speak({agi=>$AGI, text => "New user enter a new pin, then press pound." });
	my $pin = $AGI->get_data('beep', 15000, 10);
	if (!$pin) { return undef; } #pin cannot be 0 or undefined whatever start over asshole :)
	$self->debuglog(['user gave new pin:', $pin ]);
	
	#$AGI->stream_file('conf-enteringno');
	#say 'we are getting you a new account'
	#make an account give em the info.
	#get a new address for a user
	$userobj->newrec({
		userid      => 0,
		pin         => $pin,
		btc_address => 'tbd',
	})->save();
	$self->{started_new_user_id} = $userobj->record_id(); #for teardown cleanup if not completed.

	my $rpcresult = undef;
	my $userid = undef;
	#get a bitcoin address that when hashed does not collide with anything we're already doing. (probably will not collide).
	while (!$userid) {
		#should maybe get a db lock on new user creating?? (if so, probably just wrap get/release around the db lookup?? think about this)
		
		$rpcresult = $self->bitcoin_rpc({ rpc_call => { method  => 'getnewaddress', params => [ 'btcsysuser_'.$userobj->record_id() ]}, agi => $AGI });
		if ($rpcresult) {
			my $potential_userid = fnv($rpcresult);
			if (CaptchaQuest::BTCDataObj::BTCSysUser->new($self)->find({ criteria => { userid => $potential_userid }})->record_id()) {
				#umm, thats bad. thats a userid hash collision. try again bitch.
				next;
			}
			#ok, go with it!
			$userid = $potential_userid;
		}
	}

	#create userrecord with userobj save info in it.
	$userobj->set_edit_values({
		userid      => $userid,
		btc_address => $rpcresult,
		pin         => $pin,
	})->save();
	$self->{started_new_user_id} = undef; #counts as completed now. otherwise if we didnt get here, should get removed in teardown.

	#tell user about their shit. 
		#in future maybe we should cache some btc addresses and pull from cache only when we got a good signup. whatevs for now.
	my $acked = 0;
	my $uidformatted = sprintf('%010u',$userid);
	while (!$acked) {
		#$acked ||= $AGI->exec('Espeak',"'Your new syscode number is ',".ALLDIG);
		$acked ||= $self->festival_speak({agi=>$AGI, text => "Your new syscode number is" });
		$acked ||= $AGI->say_alpha($uidformatted, ALLDIG);
		$acked ||= $AGI->wait_for_digit(1000);
		#$acked ||= $AGI->exec('Espeak',"'you selected pin number',".ALLDIG);
		$acked ||= $self->festival_speak({agi=>$AGI, text => "you selected pin number" });
		$acked ||= $AGI->say_alpha($pin, ALLDIG);
		$acked ||= $AGI->wait_for_digit(2000);
		#$acked ||= $AGI->stream_file('vm-press', ALLDIG); #'press any button to acknowledge your shit';
		#$acked ||= $AGI->exec('Espeak',"'any button',".ALLDIG);
		$acked ||= $self->festival_speak({agi=>$AGI, text => "Press any button to continue to the customer menu." });
		$acked ||= $AGI->wait_for_digit(3000);
		#$acked ||= $AGI->get_data('vm-press', 15000, 1); #'press any button to acknowledge your shit';
	}
	$self->debuglog(['user should have heard their info now.', $acked ]);

	# if (!$got_btc_address) {
		# #then this never happened. you saw nothing.
		# $userobj->delete_record();
	# }
	$self->debuglog(['concluding newuser process. userobj record id is what?', $userobj->record_id() ]);
	return 1;
}

sub get_sms_messages {
	my $self = shift;
	my $args = shift;
	
	my $smsdragon_url = $self->config('smsdragon_url');

	use XML::RSS::Parser::Lite;
	use LWP::Simple;
	
	my $xml = get($smsdragon_url);
	my $rp = new XML::RSS::Parser::Lite;
	$rp->parse($xml);

	#my $from_number = '2505328905';
	my $from_number = $args->{from_number};
	my $infos = [];
	for (my $i = 0; $i < $rp->count(); $i++) {
		my $it = $rp->get($i);
		(my $from = $it->get('title')) =~ s|^\s+From\s+[\+]?(\d+).*?$|$1|; #extract just the phone number
		if ($from_number && $from !~ /\Q$from_number\E/) { next; }
		
		push (@$infos, { from => $from, btc_address => $it->get('description'), });
	}
	return $infos;
}


sub debug_explore {
	my $self = shift;

	CaptchaQuest::BTCDataObj::BTCSysUser->new($self)->create_table({alter=>1});
	CaptchaQuest::BTCDataObj::BTCSysSMSJunk->new($self)->create_table({alter=>1});
	print "in the anal";
	die "stopa";

	use Data::Dumper;
	my $validity_check = $self->bitcoin_rpc({ rpc_call => { method  => 'validateaddress', params => [ '19TDfPgNLXNGEcK9mMwBNbsoyMZ4Uqrrm5' ] } });
	if ($validity_check->{isvalid}) {
		print "TOTALLY LEGIT BITCHES \n\n";
	} else {
		print "TOTALLY MADE OF FAIL BITCHES \n\n";
	}
	print Dumper([ $validity_check ]);
	die "dragon warrior";

	my $smsdragon_url = $self->config('smsdragon_url');

	use XML::RSS::Parser::Lite;
	use LWP::Simple;
	
	my $xml = get($smsdragon_url);
	my $rp = new XML::RSS::Parser::Lite;
	$rp->parse($xml);

	my $from_number = '2505328905';
	my $infos = [];
	for (my $i = 0; $i < $rp->count(); $i++) {
		my $it = $rp->get($i);
		(my $from = $it->get('title')) =~ s|^\s+From\s+[\+]?(\d+).*?$|$1|; #extract just the phone number
		if ($from_number && $from !~ /\Q$from_number\E/) { next; }
		
		push (@$infos, { from => $from, btc_address => $it->get('description'), });
	}
		
	print Dumper([ $infos ]);
	print "\n\nFUCK ME\n";
	die "food";
	
	#my $my_tx = $self->bitcoin_rpc({ rpc_call => { method  => 'listtransactions', params => [ 'btcsysuser_17', 1 ] } }); #6 confirmations.
	#use Data::Dumper;

	my $to = '1K97JnjRNwLxRGkbaX8zHns4t52cH2dQza';

	my $userid = '3151421859';
	my $uidformatted = sprintf('%010u',$userid);
	print "stop: $uidformatted <--";
	
	die "stop: $uidformatted <--";
	
	
	my $wang = { amount => '.01' };
	my $amount = $wang->{amount};
	$amount += 0.0;
		
	my $obj = { method  => 'sendfrom', params => [ 'btcsysuser_17', $to, $amount ] };
	$obj->{version} = 1.1;
	my $rpcresult = $self->bitcoin_rpc({ rpc_call => $obj }); #6 confirmations.
	die "stoap";
	
	my $client = JSON::RPC::Client->new();
	my $json = $client->json();
	$self->dbg_print([ $json->encode($obj) ]);
	die "no";
	
	$amount = sprintf('%0.8f', $amount);
	my $userobj = CaptchaQuest::BTCDataObj::BTCSysUser->new($self); #->create_table({alter=>1});
	$userobj->load(17); #someone with some money :)
	my $rpcresult = $self->bitcoin_rpc({ rpc_call => { method  => 'sendfrom', params => [ 'btcsysuser_'.$userobj->record_id(), $to, $amount ] } }); #6 confirmations.

	die "hrm";
	my @numberfoo = (
		'.0001',
		'123.3455',
		'123.'
	);
	foreach (@numberfoo) {
		print sprintf('%0.8f', $_) . "\n";
	}

	die "no go zone";
	
	CaptchaQuest::BTCDataObj::BTCSysAddressbook->new($self)->create_table({alter=>1});
	CaptchaQuest::BTCDataObj::BTCSysUser->new($self)->create_table({alter=>1});
	my $userobj = CaptchaQuest::BTCDataObj::BTCSysUser->new($self); #->create_table({alter=>1});
	my $foo = '1GUiN4sJ9nVDashvV8a2PUNxwYZg55WDBQ';
	my $syscode = fnv($foo);
	$userobj->newrec({ 
		userid => $syscode,
		pin    => 12345,
		btc_address => $foo,
	})->save();
	print "SysCode: $syscode\n";
	
	die "no";
	my $path = '/usr/share/asterisk/sounds/en/';
	my @list = glob($path.'*.gsm');
	foreach my $file (@list) {
		(my $chopped = $file) =~ s|.*\/(.*)\.gsm|$1|;
		print $chopped . "\n";
	}
	#$self->dbg_print(\@list);
	
	return "joy";
}

sub error {
	my $self = shift;
	my $error_str = shift; #a copy of the $@ of the badness.

	$self->debuglog(["Error (PID $$): $error_str"]);
}

sub festival_speak {
	my $self = shift;
	my $args = shift;
	
	#this is because I cannot for the life of me get festival and asterisk to work together properly, and apparently, historically, i'm not the only one. code borrowed and hacked up from http://www.voip-info.org/wiki/view/Asterisk+festival+installation
	my $text = $args->{text};
	my $AGI  = $args->{agi};
	
	my $hash = md5_hex($text);
	my $sounddir = "/usr/share/asterisk/sounds/en/phoneapp/festivaltts";
	my $wavefile = "$sounddir/"."tts-$hash.wav";
	my $t2wp= "/usr/bin/";

	my $use_cache = 1;
	my $create_wav = 0;
	#file exist alrady? 
		#if so, use it. if not create id(and we care b/c we are using the cache?
	unless (-f $wavefile) {
		$create_wav = 1;
	}
	if ($create_wav) {
		if (!-w $sounddir ) {
			$self->debuglog(["error: will not be able to write data to sound tts output dir $sounddir please correct this and try again."]);
		}
		open(fileOUT, ">$sounddir"."/say-text-$hash.txt");
		print fileOUT "$text";
		close(fileOUT);
		my $execf=$t2wp."text2wave -F 8000 -o $wavefile $sounddir/say-text-$hash.txt > /dev/null";
		system($execf);
		#can remove the text file.
		unlink($sounddir."/say-text-$hash.txt");
		$self->debuglog(["festival_speak should have just created wave file here:", $wavefile ]);
	}
	#so we should have a wave file properly usable for our shit sitting there now. play it to user.
	my $streamfile = 'phoneapp/festivaltts/'.basename($wavefile,".wav");
	my $digit = $AGI->stream_file($streamfile, ALLDIG);
	$self->debuglog(["festival_speak should have just streamed this file to user: ", $streamfile ]);

	if (!$use_cache) {
		$self->debuglog(["festival_speak not using cache, and so now removing this wave file:", $wavefile ]);
		unlink($wavefile);

	}
	return $digit;
}


sub _teardown {
	my $self = shift;
	$self->debuglog(['_teardown: performing call teardown duties from SIGHUP' ]);
	
	if ($self->{started_new_user_id}) {
		$self->debuglog(['_teardown: new user did not complete the register process, remove their partially created record. todo: remove whtever btc address was alocated to them as well. record id was:', $self->{started_new_user_id} ]);
		my $userobj = CaptchaQuest::BTCDataObj::BTCSysUser->new($self); #->create_table({alter=>1});
		$userobj->load($self->{started_new_user_id})->delete_record();
	}
	
	#we may wish to clear certain cached wav files during teardown as well .. this would be the time to do it anyway.
		#probably and speak text with variables in it (need to audit this) will pointlessly bloat the cache (since they'll generally be unique by a transaction id or btc address or balance number or something) and we should really probably clear those out here.
		
	exit(0); #important or it will resume executing in main loop! with nothing connected! equals tight looping error-response-from-user badness, lol.
}
1;