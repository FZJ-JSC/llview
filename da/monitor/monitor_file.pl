#!/usr/bin/perl
# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

use strict;
use Getopt::Long;
use File::Monitor;
use Data::Dumper;
use Config::IniFiles;
use POSIX ":sys_wait_h";
use Time::HiRes qw( time sleep );
# Use internal library
use FindBin;
use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( logmsg system_call get_date _max _min check_folder );

my ($action,$actions,$actions_stat,$msg,$watchfile2action,$pid2action,$options);
my $logfile="monitor.".&get_date().".log";

# Getting sleep time for each iteration
my $sleep=1;
# File::Monitor variable
my $monitor;
# Arrays for active actions
my @timeactions;
my @intervalactions;

my $rc;

# automatic reaped when child process terminates
#$SIG{CHLD} = 'IGNORE';
# Trap to run when child processes end (CHLD signal)
$SIG{CHLD} = sub {
  while ((my $child = waitpid(-1, WNOHANG)) > 0) {
    my $action=$pid2action->{$child};
    my $rc = $? >> 8 ? $? >> 8 : 0;
    $actions->{$action}->{lastpid}  = -1;
    $actions->{$action}->{lasttime} = time()-$actions->{$action}->{startts};
    $actions->{$action}->{numcalls}++;
    $actions->{$action}->{numfailedscalls}++ if $rc;
    $actions->{$action}->{mintime} = _min($actions->{$action}->{mintime},$actions->{$action}->{lasttime});
    $actions->{$action}->{maxtime} = _max($actions->{$action}->{maxtime},$actions->{$action}->{lasttime});
    $actions->{$action}->{sumtime}+= $actions->{$action}->{lasttime};
    $msg=sprintf(" CHILD signal: process of action %s on last event [PID=%d] has terminated with error code %d (%8.4f sec)\n",
                  "'$action'",
                  $child,
                  $rc,
                  $actions->{$action}->{lasttime}
                  );
    &logmsg($msg,$logfile); &logmsg($msg,$actions->{$action}->{logfile});
  }
};

my $opt_verbose=0;
my $opt_timings=0;
my $opt_config="actions.inp";
usage($0) if( ! GetOptions( 
              'verbose'          => \$opt_verbose,
              'timings'          => \$opt_timings,
              'config=s'         => \$opt_config,
              ) );

# Reading all actions from config file
# (return $restart not used this time - it always start the server first time)
my $restart = &read_actions($opt_config);

# Starting the monitor server that will keep checking actions and signal files
# (files to be watched are added to $monitor to be scanned for changes in the infinite loop below)
&start_server();

$msg=sprintf("Start now watch loop\n"); &logmsg($msg,$logfile);

# Later perform a scan and gather any changes
# Keeps checking for changes every second (log action timings every minute)
while(1) {
  # Sleeping configured time (or default 1s)
  my $testtime=time();
  # The internal Perl sleep function is interrupted by a SIGCHLD, so here we use a workaround
  # that is using an "uninterripted sleep" that restarts the sleep if the sleep time was not reached yet
  &unint_sleep(1);
  # sleep($sleep);
  # Getting current second
  my $sec = time()%60;
  # Updating logfile
  $logfile="monitor.".&get_date().".log";

  # Checking actions that use watchtime (that should run in a given second of the minute)
  for my $action (@timeactions) {
    if ($sec==$actions->{$action}->{watchtime}) {
      # If the current second is the one given for this action, perform respective event
      $msg=sprintf("Time %d reached on action %s\n",$actions->{$action}->{watchtime},"'$action'"); &logmsg($msg,$logfile);
      &handle_event($action);
    }
  }

  # Checking actions that use intervals (that should run in after a given number of seconds)
  for my $action (@intervalactions) {
    if(time()%$actions->{$action}->{interval}==0) {
      # If the current time is a multiple of the interval given for this action, perform respective event
      $msg=sprintf("Interval %d reached on action %s\n",$actions->{$action}->{interval},"'$action'"); &logmsg($msg,$logfile);
      &handle_event($action);
    }
  }

  # Scan for changes on watchfiles or signal files
  my @changes = $monitor->scan;
  # Looping over all changes
  ACTION: for my $change (@changes) {
    # Getting action of the current change
    $action=$watchfile2action->{$change->name};
    
    # If the change was in the main config file $ENV{LLVIEW_CONF_FILE}, 
    # stops the monitor for it to be restarted with the (possible) new variables
    if($change->name eq $ENV{LLVIEW_CONF_FILE}) {
      $msg=sprintf("MAIN CONFIG file signaled via %s, stopping monitor... (make sure it will be restarted via cronjob or by hand)\n",$ENV{LLVIEW_CONF_FILE}); &logmsg($msg,$logfile);
      &shutdown_server();

      # exit now
      $msg=sprintf("Exiting...\n"); &logmsg($msg,$logfile);
      exit;
    }

    # If the change was in the config file, check if options changed 
    # (in which case, triggers a restart)
    if($change->name eq $opt_config) {
      $msg=sprintf("CONFIG file signaled via %s, checking for changes...\n",$opt_config); &logmsg($msg,$logfile);
      &check_config();

      next ACTION;
    }

    # If the change was in the shutdown signal file, shutdown monitoring
    if(($options->{auto_shutdown}) && ($change->name eq $options->{shutdown_signal_file})) {
      #  action of shutdown
      $msg=sprintf("SHUTDOWN signaled via %s\n",$options->{shutdown_signal_file}); &logmsg($msg,$logfile);
      &shutdown_server();

      # exit now
      $msg=sprintf("Exiting...\n"); &logmsg($msg,$logfile);
      exit;
    }

    # If the change was in an action watchfile, perform respective event
   
    # check if already all watchfile are updated
    $actions_stat->{$action}->{watchfile_updated}->{$change->name}=1;
    # check if all files are updated
    my $allupdated=1;
    foreach my $f (keys(%{$actions_stat->{$action}->{watchfile_updated}})) {
	$allupdated=0 if($actions_stat->{$action}->{watchfile_updated}->{$f}==0);
    }
    if($allupdated) {
	$msg=sprintf("New event on action %s file=%s\n","'$action'",$change->name); &logmsg($msg,$logfile);
	&handle_event($action);
	foreach my $f (keys(%{$actions_stat->{$action}->{watchfile_updated}})) {
	    $actions_stat->{$action}->{watchfile_updated}->{$f}=0;
	}
    } else {
	$msg=sprintf("New event on action %s file=%s (other watchfile(s) missing)\n","'$action'",$change->name); &logmsg($msg,$logfile);
    }
  #	print Dumper($change);
  }

  # Every minute, log that it is still alive and metrics
  if($sec==0) {
    $msg=sprintf("Daemon alive\n"); &logmsg($msg,$logfile) ;
    foreach $action (sort {$a cmp $b} (keys(%{$actions}))) {
      next if(!$actions->{$action}->{active}); 
      $msg=sprintf("  [%15s] -> nc=%6d (%d failed) time(min,avg,max)=(%6.2f,%6.2f,%6.2f) tbe(min,avg,max)=(%6.2f,%6.2f,%6.2f)\n",
                    $action,
                    $actions->{$action}->{numcalls},
                    $actions->{$action}->{numfailedscalls},
                    $actions->{$action}->{mintime},
                    $actions->{$action}->{sumtime}/(($actions->{$action}->{numcalls}!=0)?$actions->{$action}->{numcalls}:1),
                    $actions->{$action}->{maxtime},
                    $actions->{$action}->{mintbe},
                    $actions->{$action}->{sumtbe}/(($actions->{$action}->{numtbe}!=0)?($actions->{$action}->{numtbe}):1),
                    $actions->{$action}->{maxtbe}
                  );
      &logmsg($msg,$logfile);
    }

    # Checking if config file has changed - this is a "forced" read that happens every minute
    # because although the file may not have been modified, the commands that are expanded may
    # change (e.g., `date`)
    &check_config();
  }
}

sub check_config {
  # Reading input file every minute
  $restart = &read_actions($opt_config);
  # If something has changed, restart the server (a.k.a., the watched files, active actions)
  if ($restart) {
    #  Changes on the config file triggered restart
    $msg=sprintf("File $opt_config modified, restarting monitor\n"); &logmsg($msg,$logfile);
    &shutdown_server();
    &start_server();
  }
  return;
}

# This subroutine parses the ini configuration file
# that is used to configure the monitor and the actions
sub read_actions {
  my($fname)=@_;
  my($section,$param,$val,$newparam);
  my $restart_signal=0;
  # Parsing the ini file $fname using Config::IniFiles
  my $config_obj = Config::IniFiles->new(-file => $fname);
  
  # Looping over the sections to parse them
  foreach $section ($config_obj->Sections()) {
    if($section eq "General") {
      # Print when $options is not defined (i.e., first time):
      # Logging all sections in the file (printed only once as there's only one 'General' section)
      if(!$options) {
        $msg=sprintf("INI: Sessions in $fname:\n".join("/",$config_obj->Sections())."\n"); &logmsg($msg,$logfile);
        $msg=sprintf("INI: Keys in $section: ".join("/",$config_obj->Parameters($section))."\n"); &logmsg($msg,$logfile);
      }
      # Setting default values for $options (which is read from the General section of the ini file)
      $options->{auto_shutdown}                 = 0 if(!exists($options->{auto_shutdown}                ));
      $options->{auto_shutdown_registered}      = 0 if(!exists($options->{auto_shutdown_registered}     ));
    } else {
      # Logging current section when it does not exist
      if(!exists($actions->{$section})) {
        $msg=sprintf("INI: Keys in $section: ".join("/",$config_obj->Parameters($section))."\n"); &logmsg($msg,$logfile);
      }
      # Initialize variables and timings for actions with default timings
      $actions->{$section}->{active}          = 1    if(!exists($actions->{$section}->{active}         ));
      $actions->{$section}->{lastpid}         =-1    if(!exists($actions->{$section}->{lastpid}        ));
      $actions->{$section}->{numcalls}        = 0    if(!exists($actions->{$section}->{numcalls}       ));
      $actions->{$section}->{numtbe}          = 0    if(!exists($actions->{$section}->{numtbe}         ));
      $actions->{$section}->{numfailedscalls} = 0    if(!exists($actions->{$section}->{numfailedscalls}));
      $actions->{$section}->{timesum}         = 0    if(!exists($actions->{$section}->{timesum}        ));
      # $actions->{$section}->{mintime}         = 1e20 if(!exists($actions->{$section}->{mintime}        ));
      # $actions->{$section}->{maxtime}         = 0    if(!exists($actions->{$section}->{maxtime}        ));
      $actions->{$section}->{tbesum}          = 0    if(!exists($actions->{$section}->{tbesum}         ));
      # $actions->{$section}->{mintbe}          = 1e20 if(!exists($actions->{$section}->{mintbe}         ));
      # $actions->{$section}->{maxtbe}          = 0    if(!exists($actions->{$section}->{maxtbe}         ));
    }

    # Looping over all parameters in the current section and setting their pair key/value in variable $actions
    foreach $param ($config_obj->Parameters($section)) {
      # Getting value and removing line break
      $val=$config_obj->val($section,$param); 
      chomp($val);
      # Setting newparam=val for current session
      $newparam=$val;
      # Substituting environment variables
      $newparam =~ s/\$\{(\w+)\}/$ENV{$1}/g;
      $newparam =~ s/\$ENV\{(\w+)\}/$ENV{$1}/g;
      # Check if $newparam is a valid file or directory path
      if ($newparam =~ /^(\/|[a-zA-Z]:[\/\\]|[.]{1,2}[\/\\])/ && ($newparam =~ m!/\z! || 1)) {
        # Normalize multiple slashes to a single slash
        $newparam =~ s|/{2,}|/|g;
      }
      # Running eventual system calls between `...`
      $newparam =~ s/`(.*?)`/&system_call($1)/ge;
      # Removing leading and trailing quotes
      $newparam =~ s/^['"](.*)['"]$/$1/;
      # Logging the {parameter,value} set
      if($section eq "General") {
        if ($newparam ne $options->{$param}) {
          $options->{$param}=$newparam;
          $msg=sprintf("INI: (re)set option %-10s to %s\n","'$param'",$options->{$param}); &logmsg($msg,$logfile);
          $restart_signal = 1;
        }
      } else {
        if ($newparam ne $actions->{$section}->{$param}) {
          $actions->{$section}->{$param}=$newparam;
          $msg=sprintf("INI: action %-17s (re)set option %-15s to %s\n","'$section'","'$param'",$actions->{$section}->{$param}); &logmsg($msg,$logfile);
          $restart_signal = 1;
        }
      }
    }
  }
  # Checking if something was removed from the input
  foreach $section (keys(%{$actions})) {
    # Check if a section exist, and if not, remove it entirely from the actions
    if (!$config_obj->SectionExists($section)) {
      $msg=sprintf("INI: removing section %-17s\n","'$section'"); &logmsg($msg,$logfile);
      delete($actions->{$section});
      $restart_signal = 1;
    } else {
      # Check if a given parameter exist inside the current section, and if not remove it
      foreach $param (keys(%{$actions->{$section}})) {
        # Ignore 'restricted' keywords (which are internally used)
        next if ( grep( /^$param$/, ( 'active','lastpid','numcalls','numtbe','numfailedscalls','timesum','mintime',
                                      'maxtime','tbesum','mintbe','maxtbe','sumtbe','lasttbe','lasttime','starttstbe',
                                      'sumtime','startts','lasttime','sumtime','starttstbe','startts') ) );
        if (!$config_obj->exists($section, $param)) {
          $msg=sprintf("INI: action %-17s removing option %-15s\n","'$section'","'$param'"); &logmsg($msg,$logfile);
          delete($actions->{$section}->{$param});
          $restart_signal = 1;
        } 
      }
    }
  }
  return $restart_signal;
}

sub start_server {
  my($action,$numsubprocs);

  $msg=sprintf("Starting monitor daemon\n"); &logmsg($msg,$logfile);

  # Module to monitor files for changes
  $monitor = File::Monitor->new();

  # register actions: files for active actions are added to $monitor to be watched for changes in every $monitor->scan call
  # Each action can use one of the following update methods (from higher to lower priority):
  # watchfile: when the file is changed, the action is triggered
  # watchtime: an integer from 0 to 59 to indicate which second of the minute the action should run (i.e., the action runs once per minute)
  # interval: the interval (in seconds) at which the action will run
  foreach $action (keys(%{$actions})) {
    if($actions->{$action}->{active}) {
	if(exists($actions->{$action}->{watchfile})) {
	    $msg=sprintf("Register action %-15s [%s]\n","'$action'",$actions->{$action}->{watchfile}); &logmsg($msg,$logfile);
	    foreach my $file (split(/\s*,\s*/,$actions->{$action}->{watchfile})) {
		$monitor->watch($file);
		$watchfile2action->{$file}=$action;
		$actions_stat->{$action}->{watchfile_updated}->{$file}=0;
	    }
      } elsif(exists($actions->{$action}->{watchtime})) {
        $msg=sprintf("Register action %-15s [At every :%d s of the minute]\n","'$action'",$actions->{$action}->{watchtime}); &logmsg($msg,$logfile);
        push(@timeactions, $action);
      } elsif(exists($actions->{$action}->{interval})) {
        $msg=sprintf("Register action %-15s [Every %d s]\n","'$action'",$actions->{$action}->{interval}); &logmsg($msg,$logfile);
        push(@intervalactions, $action);
      }
    }
  }

  # register signal file 'shutdown_signal_file' for changes
  if(exists($options->{auto_shutdown}) && exists($options->{shutdown_signal_file})) {
    if($options->{auto_shutdown}) {
      if(!$options->{auto_shutdown_registered}) {
        $msg=sprintf("Register shutdown_signal_file %s\n",$options->{shutdown_signal_file}); &logmsg($msg,$logfile);
        $monitor->watch($options->{shutdown_signal_file});
        $options->{auto_shutdown_registered}=1;
      }
    }
  }

  # register current file to read changes when it is modified (this check/scan is made every second,
  # but we still need a "forced" read every minute to ensure the expanded strings - for example `date` -
  # are changed)
  $msg=sprintf("Register current config file %s\n",$opt_config); &logmsg($msg,$logfile);
  $monitor->watch($opt_config);

  # register main configuration file LLVIEW_CONF_FILE to be monitored (to update env vars in case they are changed)
  if(defined($ENV{LLVIEW_CONF_FILE})) {
    $msg=sprintf("Register main config file %s\n",$ENV{LLVIEW_CONF_FILE}); &logmsg($msg,$logfile);
    $monitor->watch($ENV{LLVIEW_CONF_FILE});
  }

  # First scan just finds out about the monitored files. No changes will be reported.
  $msg=sprintf("Run first scan\n"); &logmsg($msg,$logfile);
  $monitor->scan;
}

sub shutdown_server {
  my($action,$numsubprocs,$cnt);
  my $running_actions;
  my $running_pids;

  # Checking how many actions are still running
  ($running_actions,$running_pids) = &running_actions();
  $numsubprocs = scalar @{$running_actions};

  # Waiting for the tasks to end
  $cnt=0;
  while($numsubprocs>0) {
    $msg=sprintf("Waiting for %d sub-process(es) to be finished: %s (%d sec)\n",$numsubprocs,join(",",@{$running_actions}),$cnt); &logmsg($msg,$logfile);

    sleep(1); $cnt++;
    # Updating running processes
    ($running_actions,$running_pids) = &running_actions();
    $numsubprocs = scalar @{$running_actions};

    ## IMPORTANT: Trying to kill the processes results in orphan children and gran-children, 
    ## even when sending negative signal to kill the whole PID group. Therefore, this was removed
    ## and the monitor has to just wait for the children to finish.
    # If waittime is longer than $maxwaittime min, kill remaining jobs
    # if (($cnt>$maxwaittime)&&($numsubprocs>0)) {
    #   # $msg=sprintf("Process(es) PIDs stuck for more than ${maxwaittime}s: %s. Killing them...\n",join(",",@{$running_pids})); &logmsg($msg,\*STDERR);
    #   $msg=sprintf("Process(es) PIDs stuck for more than ${maxwaittime}s: %s. Killing them... ",join(",",@{$running_pids})); &logmsg($msg,\*STDERR);
    #   # Killing children and their own children (killing the pid group with '-KILL')
    #   kill '-KILL', @{$running_pids};
    #   waitpid(-1,0);
    #   $msg=sprintf("Done!\n"); &logmsg($msg,\*STDERR);
    #   last;
    # }
  }
  $msg=sprintf("Finished waiting for sub-processes!\n"); &logmsg($msg,$logfile);

  # Shutting down monitor: removing variable and de-registering options
  $msg=sprintf("Shutting down monitor\n"); &logmsg($msg,$logfile);
  undef $monitor;
  @timeactions = ();
  @intervalactions = ();
  $options->{auto_shutdown_registered}=0 if ($options->{auto_shutdown_registered});

}

# Active actions are evaluated by querying the operating system.
# Signal 0 is utilized to verify process existence safely without interfering with 
# the SIGCHLD reaping mechanism.
sub running_actions {
  my @running_actions;
  my @running_pids;
  foreach $action (keys(%{$actions})) {
    if($actions->{$action}->{lastpid}>0) {
      # Confirming that PID exists to wait for it
      # The OS is queried to confirm the PID is still actively running.
      if (kill(0, $actions->{$action}->{lastpid})) {
        # PID exists, add to list
        push(@running_actions, "$action [PID:$actions->{$action}->{lastpid}]") ;
        push(@running_pids, $actions->{$action}->{lastpid}) ;
      } else {
        # If it does not exist, don't count it and reset tracker (set lastpid to -1)
        $msg=sprintf("Action $action process [PID:$actions->{$action}->{lastpid}] does not exist! (missed SIGCHLD?) Removing...\n"); &logmsg($msg,\*STDERR);
        $actions->{$action}->{lastpid} = -1;
      }
    }
  }
  return \@running_actions,\@running_pids;
}


sub handle_event {
  my($action)=@_;
  
  # accounting
  my $ntime=time();
  # Time between action repetitions
  if($actions->{$action}->{starttstbe}>0) {
    $actions->{$action}->{numtbe}++;
    $actions->{$action}->{lasttbe}=$ntime-$actions->{$action}->{starttstbe};
    $actions->{$action}->{mintbe}=_min($actions->{$action}->{mintbe},$actions->{$action}->{lasttbe});
    $actions->{$action}->{maxtbe}=_max($actions->{$action}->{maxtbe},$actions->{$action}->{lasttbe});
    $actions->{$action}->{sumtbe}+=$actions->{$action}->{lasttbe};
  }
  $actions->{$action}->{starttstbe}=$ntime;

  # Check if last action has terminated
  if($actions->{$action}->{lastpid}>=0) {
    # If last action is still running
    $msg=sprintf(" WARNING: Process of last event [PID=%6d] of action %s has NOT terminated, ignore event\n",$actions->{$action}->{lastpid},"'$action'");
    &logmsg($msg,$logfile); &logmsg($msg,$actions->{$action}->{logfile});
    $actions->{$action}->{numfailedscalls}++;
  } else {
    # Action not running, ready to fork
    my $pid = fork;
    if (not defined $pid) {
      $msg=sprintf(" ERROR: Could not fork for action %s\n","'$action'"); &logmsg($msg,$logfile); &logmsg($msg,$actions->{$action}->{logfile});
      return(0);
    }
    if ($pid) { # parent process
      $actions->{$action}->{lastpid}=$pid;
      $actions->{$action}->{startts}=$ntime;
      $pid2action->{$pid}=$action;
      $msg=sprintf(" PARENT fork process with child pid %d for action %s\n",$pid,"'$action'"); &logmsg($msg,$actions->{$action}->{logfile});
    } else { # child process
      $msg=sprintf(" CHILD %d start action %s\n",$pid,"'$action'"); &logmsg($msg,$actions->{$action}->{logfile});
      my $execcmd=$actions->{$action}->{execute};
      $execcmd=~s/^[\"\']//gs; $execcmd=~s/[\"\']$//gs; $execcmd=~s/^[\(]//s; $execcmd=~s/[\)]$//s;
      my $cmd="(cd $actions->{$action}->{execdir}; (".$execcmd.") >> $actions->{$action}->{logfile} 2>&1 )";
      &check_folder("$actions->{$action}->{execdir}/");
      $msg=sprintf(" CHILD %d start cmd %s\n",$pid,$cmd); &logmsg($msg,$actions->{$action}->{logfile});
      $rc = system($cmd);
      $rc = $rc >> 8?$rc >> 8:0;
      $msg=sprintf(" CHILD %d end action %s\n",$pid,"'$action'"); &logmsg($msg,$actions->{$action}->{logfile});
      exit $rc;
    }
  }
}


# Adapted from https://stackoverflow.com/a/12093174/3142385
sub unint_sleep($) {
  my $sleep_til = time + $_[0];
  while (1) {
    my $sleep_dur = $sleep_til - time;
    last if $sleep_dur <= 0;
    sleep($sleep_dur);
  }
}
