package LML_jobreport;

my $VERSION='$Revision: 1.00 $';
my($debug)=0;

use strict;
use constant  {
    FSTATUS_UNKNOWN => -1,
    FSTATUS_NOT_EXISTS => 0,
    FSTATUS_EXISTS => 1,
    FSTATUS_COMPRESSED => 2,
    FSTATUS_TOBEDELETED => 3,
    FSTATUS_DELETED => 4,
    FSTATUS_TOBECOMPRESSED => 5,
    FACTION_COMPRESS => 1,
    FACTION_ARCHIVE => 2,
    FACTION_REMOVE => 3
};

sub get_status_desc {
    my($stat)=@_;
    return("FSTATUS_UNKNOWN") if($stat==FSTATUS_UNKNOWN);
    return("FSTATUS_NOT_EXISTS") if($stat==FSTATUS_NOT_EXISTS);
    return("FSTATUS_EXISTS") if($stat==FSTATUS_EXISTS);
    return("FSTATUS_COMPRESSED") if($stat==FSTATUS_COMPRESSED);
    return("FSTATUS_TOBEDELETED") if($stat==FSTATUS_TOBEDELETED);
    return("FSTATUS_DELETED") if($stat==FSTATUS_DELETED);
    return("FSTATUS_TOBECOMPRESSED") if($stat==FSTATUS_TOBECOMPRESSED);
    return("UNKNOWN");
}

1;
