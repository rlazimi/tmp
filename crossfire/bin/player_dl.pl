#!/usr/bin/perl -w
##################
# Playerfile download utility.
# Version 1.2
####
# Note: This file requires the CGI.pm module to operate.
# The player_dl.html file is a basic web page which
# can be used for downloads.
#
# This CGI script allows players to download their players
# files through a web interface.  It does password checking
# and has some extra options.  
#
# Note 2: The player files and directories need to be readable
# by whatever uid runs this program.  In many cases, this may be
# nobody or apache or whatever.  This script does not differentiate
# invalid password or lack of ability to read player files.  If
# you get invalid name/password combos and you're sure you're
# entering them correctly, check file permissions.
#
# Note 3: on some systems, differnet password encryption schemes
# are used.  Eg, on windows, no encryption is used at all, while
# on others, if des_crypt is available, that is used instead.
# this script would need modification to cover those cases.
#
####
# Copyright (c) 2003 by Philip Stolarczyk
# This  program  is  free  software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License  as  published  by  the  Free Software Foundation;
# either version 2 of the License, or (at your  option)  any
# later version.
# This  program  is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty  of  MERCHANTABILITY  or FITNESS FOR A PARTICULAR
# PURPOSE.  See the GNU  General  Public  License  for  more
# details.
####
#   Config options:
#
# Where the tar program is located. 
$tar = '/bin/tar';

$prefix="/usr/games/crossfire";
# Where the crossfire directory is located.
$crossfire_home = "${prefix}/var/crossfire/players";

# Where to save temporary files
$temp_dir = '/tmp';

# How often a player can have their file sent to them, in seconds. (ie. 3600 is once/hour), set to 0 to disable.
$timelimit = 3600;

# Where to save information on when which player files were downloaded, for the time limit function.
$statefile = "$temp_dir/pldl.dat";

# Whether to delete the player's file after they download it.
$delete_player = 0;

#
####
# BUGS:
#  Systems that do NL to CRLF interpretation on CGI output
#	will corrupt the .tar file.  This includes Microsoft
#	Windows systems.  I haven't found any solution.
##################
# Code begins.

use CGI;
use CGI::Carp 'fatalsToBrowser';
$CGI::POST_MAX=1024;  # max 1K posts
$CGI::DISABLE_UPLOADS = 1;  # no uploads

$q = new CGI;

# Verify that player name contains no invalid characters. 
$playername = '';
$playername = $q->param('playername') if $q->param('playername');
$playername =~ s/[^A-Za-z_\-]//g;	# No invalid chars
$playername =~ s/^(.{1,64}).*$/$1/;	# Max 64 chars, (really it's 16 or 32 in the server)

# Default to not validated, until the password is checked.
$valid = 0;

# No error to report yet.
$errormsg = '';

# We want to the time we ran to be consistent, even if it takes a couple seconds.
$time = time();


# Validate password
$password = $q->param('password');
if ($playername) { # Make sure that the user typed in a playername.
	if ((open PLAYERFILE, "$crossfire_home/$playername/$playername.pl") # Make sure the player's file exists
	or (open PLAYERFILE, "$crossfire_home/$playername/$playername.pl.dead")) { # Or use the dead file, if no player is alive
		foreach (<PLAYERFILE>) {
			chomp; chomp;
			# Do actual checking of password.
			if ( /^password (.*)$/ ) {
			    $cp = crypt($password,$1);
			    if ($cp eq $1)  {
				$valid = 1;
			    }
			}
		}
		close PLAYERFILE;
	}
}
if (!$valid) { $errormsg = 'Invalid username or password' };

# If the player is validated, and we're limiting how often players can download their files, do so.
if ($valid and $timelimit and $statefile) {
	open STATEFILE, "<$statefile";
	@contents = <STATEFILE>;
	close STATEFILE;
	# Don't allow more than 1024 players to download their files per $timelimit seconds.
	# This is to prevent STATEFILE from getting too large.
	if ($#contents > 1024) {
		$valid = 0;
		$errormsg = 'Too many players have tried to download their files recently.  Please wait a bit before trying again.\n';
	}

	# Check timestamp of last download for this player
	foreach (@contents) {
		chomp; chomp;
		if (/^DL $playername (.*)$/) {
			# $1 is the last time the file was DLed.
			if ($time > ($timelimit + $1)) {
				$valid = 0;
				$errormsg = 'You just downloaded your file.  Wait a bit before trying again.';
			}
		}
	}
}

if ($valid) {
	# Create and send file

	# Create a new archive
	# Sending binary data.
	# Add content-disposition, in this way, the browser (at least mozilla)
	# will use it as the default filename, instead of the cgi script name.
	print $q->header(-type=>"application/x-compressed-tar",
			 "-content-disposition"=>"inline; filename=\"$playername.tar\"");

	# Change to player directory, so that long pathname is not included in
	# sent file.
	chdir("$crossfire_home");
	# archive up the player
	system("$tar  -cf - $playername");

	# 'Delete' player's files, if applicable.  (technically rename them, to hide from server.)
	if ($valid and $delete_player) {
		@files= glob("$crossfire_home/$playername/*");
		# Rename all files except *.tar
		foreach (@files) { 
			next if ( /\.tar$/i );
			rename $_, "$_.downloaded";
		}
	}

    # Set timestamp of last download for this player, if applicable.
    # Also, remove outdated player download timestamps, if applicable.
    if ($timelimit > 0 and $statefile) {
	if (open STATEFILE, "<$statefile") {
		@contents = <STATEFILE>;
		close STATEFILE;
	} else {
		@contents = ();
	}

	if (open STATEFILE, ">$statefile") {
		foreach (@contents) {
			chomp; chomp;
			if (/^DL (.*) (.*)$/) {
				# All lines starting with DL are download time records.
				my ($playerdownloaded, $timedownloaded) = ($1, $2);

				# If this player just downloaded their file, don't copy them yet.  We update their timestamp later.
				next if ($valid and ($playerdownloaded eq $playername));
				# If this record has expired, don't copy it.
				next if (($timedownloaded + $timelimit) < $time);
				# Otherwise, copy the record to the new state file.
				print "$_\n";
			} else {
				# Allow other lines in this file.
				print "$_\n";
			}
		}
		# If this player downloaded their file, save it.
		if ($valid) {
			print STATEFILE "DL $playername $time\n";
		}
		close STATEFILE;
	} else {
		die "Unable to save state to file $statefile.\n";
	}
    }
}

# If no file was sent, send a form and any error messages.
if (!$valid) {
	print $q->header('text/html');

	# Print header
	print $q->start_html('Download your player file');
	print "\n\n\n";

	# print any error message that may have occured.
	if ($errormsg) {
		print $q->h3("ERROR: ". $errormsg), $q->br(), $q->br();
	}

	# Print warnings if $delete_player is enabled.
	if ($delete_player) {
		print <<'(END)';
<pre><font color="#FF0000">WARNING:</font>
Downloading your file will remove it from the server.  If the
download fails, contact the system administrator, and they may
be able to retrieve the file.
</pre>
(END)
	}

	print $q->h2("Download your player file:");

	# Print generic form to allow player to download their file.
	print $q->start_form(),
		'Character name: ', $q->textfield('playername'), $q->br(),
		'Character password: ' , $q->password_field('password'), $q->br(),
		$q->submit('Download'), $q->reset('Clear Entries'), $q->end_form();

	print $q->end_html();
}
