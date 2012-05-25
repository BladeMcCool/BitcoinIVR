readme:
the ivr system code is all scripts/btc.pl . it is pretty basic but it works.
everything else is just support stuff. i need to spend some time decoupling this app from the messy custom framework that it was written under. but it should work as is.

depends on 
	- bitciond 0.3.x (but you should really install at least 0.6.2 instead and make sure it works on that!)
	- Perl (and a bunch of CPAN modules for which it'll complain about anything that is missing), 
	- asterisk, 
	- festival tts, 
	- mysql db (but you could probably use any db if you are willing to hack in any changes required in the sql abstraction code, lol!)
	- ridiculous custom SpApp framework (included)

notes: (I'm writing this 6 months after the fact, probably not 100% complete or correct)
	- many paths to things like config files, .wav file directories, etc are hardcoded in the btc.pl script. probably should put more things into the phoneapp.conf config file ($self->config('optionname') to access from code)
	- phoneapp.conf file can go in /etc/asterisk/phoneapp/conf/ directory ... also ensure /etc/asterisk/phoneapp is writeable by AGI as that is where it will want to create a debuglog file (which you can run tail -f on to see what the code is doing). NOTE: This is where you must set the mysql connection info as well.
	- mysql tables can be created by executing the included scripts/btcivr_schema_adjust.pl (additionally, there is now included a scripts/btcivr_schema.sql schema produced via mysqldump)
	- asterisk sip.conf needs entry to route incoming SIP call to correct context. sample entry included in example conf dir
	- asterisk extensions.conf needs entries to route incoming sip calls to application context. sample entries included in example conf dir.
	- on my system all the sounds files go into /usr/share/asterisk/sounds/en/phoneapp/ (inside phoneapp, a subdirectory called 'festivaltts' needs to be created and writeable by AGI/asterisk, where on-the-fly wav files for speaking to user will be stored (kludge because i could NOT get the Festival asterisk extension to work properly))
	- stuff was written for bitcoind 0.3.x RPC. I haven't tested it against any higher versions, but it never really did anything overly complex anyway, so it might just work as-is on latest bitcoind.
	- SMS services were originally purchased from 'SMS Dragon' who provided a unique/secret URL that essentially just provided a RSS feed of all SMS messages sent to it. Not the most ideal but it was enough for me to work with. You can probably find better that let you query by sender-number or something and not have to deal with giant ever expanding rss feeds. lol.
	
motivation:
	- Originally it was the use case of "How can my grandma send and receive a Bitcoin" (or anyone in Asia/Africa who might have only voice+sms services).
	
apologies:
	- The code is not the most well organized and there may be offensive swearing in some of the code comments.
	- I dont have a handy list of the full dependencies that the framework code will complain about being missing if not installed. I generally have to run through resolving those one by one in a painful process. I also try real hard not to think about server configuraiton related stuff and try to focus on writing code whenever possible. And I'm sometimes inconsistent in my naming of things.
	- I did not actually use any version control because ... well I'm pretty much a one man show, and somewhat of a total-hack. Sorry about that.

license:
	GPL i guess. or MIT. or .. actually I dont really care. how about public domain. Nov 2011.
	
patronage:
	i may or may not control this bitcoin address: 1Mav9nDfToU3KrhBWsWdEe3AsTaoaeDmGZ
	but if anyone sends anything there I'll know you care.
	