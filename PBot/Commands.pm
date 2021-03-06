# File: Commands.pm
# Author: pragma_
#
# Purpose: Derives from Registerable class to provide functionality to
#          register subroutines, along with a command name and admin level.
#          Registered items will then be executed if their command name matches
#          a name provided via input.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Commands;

use warnings;
use strict;

use base 'PBot::Registerable';

use Carp ();
use Text::ParseWords qw(shellwords);

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Commands should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->SUPER::initialize(%conf);

  my $pbot = delete $conf{pbot};
  if(not defined $pbot) {
    Carp::croak("Missing pbot reference to PBot::Commands");
  }

  $self->{pbot} = $pbot;
  $self->{name} = undef;
  $self->{level} = undef;
}

sub register {
  my ($self, $subref, $name, $level) = @_;

  if((not defined $subref) || (not defined $name) || (not defined $level)) {
    Carp::croak("Missing parameters to Commands::register");
  }

  $name = lc $name;

  my $ref = $self->SUPER::register($subref);

  $ref->{name} = $name;
  $ref->{level} = $level;

  return $ref;
}

sub unregister {
  my ($self, $name) = @_;

  if(not defined $name) {
    Carp::croak("Missing name parameter to Commands::unregister");
  }

  $name = lc $name;

  @{ $self->{handlers} } = grep { $_->{name} ne $name } @{ $self->{handlers} };
}

sub exists {
  my $self = shift;
  my ($keyword) = @_;

  $keyword = lc $keyword;
  foreach my $ref (@{ $self->{handlers} }) {
    return 1 if $ref->{name} eq $keyword;
  }
  return 0;
}

sub interpreter {
  my ($self, $stuff) = @_;
  my $result;

  if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
    use Data::Dumper;
    $Data::Dumper::Sortkeys  = 1;
    $self->{pbot}->{logger}->log("Commands::interpreter\n");
    $self->{pbot}->{logger}->log(Dumper $stuff);
  }

  my $from = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $stuff->{from};
  my $admin = $self->{pbot}->{admins}->loggedin($from, "$stuff->{nick}!$stuff->{user}\@$stuff->{host}");
  my $level = defined $admin ? $admin->{level} : 0;
  my $keyword = lc $stuff->{keyword};

  if (exists $stuff->{'effective-level'}) {
    $self->{pbot}->{logger}->log("override level to $stuff->{'effective-level'}\n");
    $level = $stuff->{'effective-level'};
  }

  foreach my $ref (@{ $self->{handlers} }) {
    if ($ref->{name} eq $keyword) {
      if ($level >= $ref->{level}) {
        $stuff->{no_nickoverride} = 1;
        my $result = &{ $ref->{subref} }($stuff->{from}, $stuff->{nick}, $stuff->{user}, $stuff->{host}, $stuff->{arguments}, $stuff);
        if ($stuff->{referenced}) {
          return undef if $result =~ m/(?:usage:|no results)/i;
        }
        return $result;
      } else {
        return undef if $stuff->{referenced};
        if ($level == 0) {
          return "/msg $stuff->{nick} You must login to use this command.";
        } else {
          return "/msg $stuff->{nick} You are not authorized to use this command.";
        }
      }
    }
  }

  return undef;
}

sub parse_arguments {
  my ($self, $arguments) = @_;
  my $args = quotemeta $arguments;
  $args =~ s/\\ / /g;
  return shellwords($args);
}

1;
