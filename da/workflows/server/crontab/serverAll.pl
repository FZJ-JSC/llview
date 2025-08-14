#!/usr/bin/perl
# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Carsten Karbach (Forschungszentrum Juelich GmbH) 
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

use strict;
# Use internal library
use FindBin;
use lib "$FindBin::RealBin/../../../lib";
use LML_da_util qw( get_date remove_old_logs check_folder );

# Folder definitions
my $LLVIEW_SYSTEMNAME = $ENV{'LLVIEW_SYSTEMNAME'}; 
my $LLVIEW_HOME = $ENV{'LLVIEW_HOME'};
my $LLVIEW_DATA = $ENV{'LLVIEW_DATA'};
my $LLVIEW_CONF = $ENV{'LLVIEW_CONF'};
my $prefix = "crontab_server"; # prefix for log/err files


# Defining log and error files
my $logs="$LLVIEW_DATA/$LLVIEW_SYSTEMNAME/logs/";
# Checking if logs folder exist, and if not, creates it
&check_folder($logs);
my $logfile = "$logs/$prefix.".&get_date().".log";
my $errfile = "$logs/$prefix.".&get_date().".errlog";

# Removing older log/err files (older than days defined in $LLVIEW_LOG_DAYS in .llview_server_rc)
my $logdays = ($ENV{'LLVIEW_LOG_DAYS'} =~ '^[0-9]+$') ? $ENV{'LLVIEW_LOG_DAYS'} : 1;
&remove_old_logs($logs,$logdays,$logfile);

# If signal file exists, does not run any job
my $shutdown = $ENV{'LLVIEW_SHUTDOWN'} ? $ENV{'LLVIEW_SHUTDOWN'} : "$ENV{HOME}/HALT_ALL";
if(-f $shutdown) {
  my $cmd = qq{cd $logs; echo "[`date +'%D %T'`] Shutdown file $shutdown found. Exiting..." >> $logfile };
  system($cmd);
  exit;
}

# Commands for monitor
my $searchCmdMonitor = "perl $LLVIEW_HOME/da/monitor/monitor_file.pl --config $LLVIEW_CONF/server/workflows/actions.inp";
my $startMonitor = "cd $logs; $searchCmdMonitor 1>> $logfile 2>> $errfile &";
# Checking if llview monitor is running
restartProg($searchCmdMonitor, $startMonitor);

if(0) {
    for my $cnt ("00") {
       my $startmmpmon = "cd $LLVIEW_DATA/$LLVIEW_SYSTEMNAME/mmpmon; $LLVIEW_CONF/server/workflows/start_select_jedi_mmpmon${cnt}.sh";
       my $searchCmdmmpmon = "/usr/bin/perl -w /home/llstat/llview/da/rms/GPFS/select_mmpmon_tail.pl -name jedi${cnt} ";
       restartProg($searchCmdmmpmon, $startmmpmon);
    }
}

# (JuRepTool was moved to an action in actions.inp, but this part 
# was kept here commented out in case it is preferred to be used)
# Checking if JuReptool is running
# my $jureptool = "$LLVIEW_HOME/jureptool";
# my $nprocs = ($ENV{'JUREPTOOL_NPROCS'} =~ '^[0-9]+$') ? $ENV{'JUREPTOOL_NPROCS'} : 2;
# if ( $nprocs > 0 ) {
#   # folder used by jureptool for temporary files (lastmod and reports), as well as shutdown file (to shutdown only jureptool)
#   my $folder = "$LLVIEW_DATA/$LLVIEW_SYSTEMNAME/jureptool/";
#   &check_folder($folder);
#   &check_folder("$folder/results/"); # folder required for temporary reports

#   my $searchCmdjureptool = "$ENV{PYTHON} $jureptool/src/main.py --configfolder $ENV{LLVIEW_CONF}/jureptool --shutdown $ENV{LLVIEW_SHUTDOWN} $folder/shutdown";
#   my $startjureptool = "cd $folder; nice -n 19 $searchCmdjureptool --nohtml --gzip --nprocs $nprocs --daemon --loglevel DEBUG $LLVIEW_DATA/$LLVIEW_SYSTEMNAME/tmp/jobreport/tmp/plotlist.dat --logprefix $LLVIEW_DATA/$LLVIEW_SYSTEMNAME/logs/jureptool 1>> $LLVIEW_DATA/$LLVIEW_SYSTEMNAME/logs/jureptool.log 2>> $LLVIEW_DATA/$LLVIEW_SYSTEMNAME/logs/jureptool.errlog &";  
#   restartProg($searchCmdjureptool, $startjureptool);
# }

#**************************************************************
#
# Check if the passed command is running. If not, run the command.
# The command is expected to run continuosly.
#
# @param $_[0] the command which is checked to be running
#
# @param $_[1] the command to restart the first command, in case of not running
#
# @return 1, if the command was restarted, 0 otherwise
#
#**************************************************************
sub restartProg{

  my $cmd = shift;            # The command that should be running
  my $restartCommand = shift; # Full command to run in case it is not running

  my $progcount = `ps -ef | grep '$cmd' | grep -v $0 | grep -v "grep" | wc -l`;

  if($progcount < 1){
    my $cmd = qq{echo "[`date +'%D %T'`] Cronjob not running, (re)starting with command:\n $restartCommand" >> $logfile; $restartCommand};
    system($cmd);
    return 1;
  }

  return 0;
}
