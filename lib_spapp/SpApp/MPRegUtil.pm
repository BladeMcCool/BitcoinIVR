package SpApp::MPRegUtil;
use base 'SpApp::Core';
use strict;

#attempting to move these here so standalone util can run on systems without modperl2.
use SpApp::CAPApache2 qw(:all); #my hacked up CGI::Application::Plugin::Apache
use SpApp::CAPARRipAPReq; #my hacked up CGI::Application::Plugin::Apache::Request;
#use CGI::Application::Plugin::Apache qw(:all);
#use CGI::Application::Plugin::Apache::Request;

1;