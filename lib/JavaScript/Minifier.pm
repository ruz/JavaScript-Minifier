# JavaScript::Minifier 2006-06-30
# Author: Eric Herrera
# This work is a translation from C to Perl of jsmin.c published by
# Douglas Crockford.  Permission is hereby granted to use the Perl
# version under the same conditions as the jsmin.c on which it is
# based.
#
# /* jsmin.c
#    2003-04-21
# 
# Copyright (c) 2002 Douglas Crockford  (www.crockford.com)
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# The Software shall be used for Good, not Evil.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# */


package JavaScript::Minifier;
use strict;
use warnings;

our $VERSION = '0.01';

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(jsmin);

sub jsmin {
  my $in = shift;
  my $out = shift;
  my $obj = new JavaScript::Minifier;
  return $obj->minify($in, $out); 
}

sub isAlphanum {
  my $c = shift;
  #return true if the character is a letter, digit, underscore,
  #      dollar sign, or non-ASCII character.
  
  return (($c ge 'a' && $c le 'z') || ($c ge '0' && $c le '9') ||
          ($c ge 'A' && $c le 'Z') || $c eq '_' || $c eq '$' || $c eq '\\' ||
          ($c ne 'None' && ord($c) > 126));
}

sub new {
  my $class = shift;
  
  my $self = {};
  bless $self, $class;
  
  return $self;
}

sub _out {
  my $self = shift;
  my $data = shift;
  
  my $out = $self->{'outstream'};
  if (!$out){
    $self->{'data'} .= $data;
  }
  else {
    print $data;
  }
}
sub _outA { 
  my $self = shift; 
  return $self->_out($self->{'theA'});
}
 
sub _outB { 
  my $self = shift;
  return $self->_out($self->{'theB'});
}


sub _get(){
  my $self = shift;
  # return the next character from stdin. Watch out for lookahead. If
  # he character is a control character, translate it to a space or
  # linefeed.

  my $c = $self->{'theLookahead'};
  $self->{'theLookahead'} = 'None';
  if ($c eq 'None'){
    if ($self->{'indata'}){
      $c = substr($self->{'indata'}, $self->{'indata_pos'}++, 1);
    }
    else {
      read($self->{'instream'}, $c, 1);
    }
  }
  if ($c ge ' ' || $c eq "\n"){
    return $c;
  }
  if ($c eq ''){ # EOF
    return '\000';
  }
  if ($c eq "\r"){
    return "\n";
  }
  return ' ';
}
   
sub _peek(){
  my $self = shift;
  $self->{'theLookahead'} = $self->_get();
  return $self->{'theLookahead'};
}

sub _next(){
  my $self = shift;
  my $c;
  my $p;
  
  #get the next character, excluding comments. peek() is used to see
  #     if a '/' is followed by a '/' or '*'.
  $c = $self->_get();
  if ($c eq '/'){
    $p = $self->_peek();
    if ($p eq '/'){
      $c = $self->_get();
      while ($c gt "\n"){
        $c = $self->_get();
      }
      return $c;
    }
    if ($p eq '*'){
      $c = $self->_get();
      while (1){
        $c = $self->_get();
        if ($c eq '*'){
          if ($self->_peek() eq '/'){
            $self->_get();
            return ' ';
          }
        }
        if ($c eq '\000'){
          die "UnterminatedComment";
        }
      }
    }
  }
  return $c;
}

sub _action(){
  my $self = shift;
  my $action = shift;
  # do something! What you do is determined by the argument:
  #   1   Output A. Copy B to A. Get the next B.
  #   2   Copy B to A. Get the next B. (Delete A).
  #   3   Get the next B. (Delete B).
  #     action treats a string as a single character. Wow!
  #     action recognizes a regular expression if it is preceded by ( or , or =.

  if ($action <= 1){
    $self->_outA();
  }    
  if ($action <= 2){
    $self->{'theA'} = $self->{'theB'};
    if ($self->{'theA'} eq "'" or $self->{'theA'} eq '"'){
      while (1){
        $self->_outA();
        $self->{'theA'} = $self->_get();
        if ($self->{'theA'} eq $self->{'theB'}){
          last;
        }
        if ($self->{'theA'} le "\n"){ 
          die "UnterminatedStringLiteral $self->{'theA'}";
        }
        if ($self->{'theA'} eq '\\'){
          $self->_outA();
          $self->{'theA'} = $self->_get();
        }
      }
    }
  }
  if ($action <= 3){
    $self->{'theB'} = $self->_next();
    if ($self->{'theB'} eq '/' && ($self->{'theA'} eq '(' || $self->{'theA'} eq ',' || $self->{'theA'} eq '=')){
      $self->_outA();
      $self->_outB();
      while (1){
        $self->{'theA'} = $self->_get();
        if ($self->{'theA'} eq '/'){
          last;
        }
        elsif ($self->{'theA'} eq '\\'){
          $self->_outA();
          $self->{'theA'} = $self->_get();
        }
        elsif ($self->{'theA'} le "\n"){ 
          die "UnterminatedRegularExpression";
        }
        $self->_outA();
      }
      $self->{'theB'} = $self->_next();
    }
  }
}

sub _jsmin(){
  my $self = shift;

  my %list1 = map { $_ => 1 } ('{', '[', '(', '+', '-');
  my %list2 = map { $_ => 1 } ('}', ']', ')', '+', '-', '"', '\'');
  
  # Copy the input to the output, deleting the characters which are
  # insignificant to JavaScript. Comments will be removed. Tabs will be
  # replaced with spaces. Carriage returns will be replaced with linefeeds.
  # Most spaces and linefeeds will be removed.
  $self->{'theA'} = "\n";
  $self->_action(3);

  while ($self->{'theA'} ne '\000'){
    if ($self->{'theA'} eq ' '){
      if (isAlphanum($self->{'theB'})){
        $self->_action(1);
      }
      else {
        $self->_action(2);
      }
    }
    elsif ($self->{'theA'} eq "\n"){
      if ($list1{$self->{'theB'}}){
        $self->_action(1);
      }
      elsif ($self->{'theB'} eq ' '){
        $self->_action(3);
      }
      else {
        if (isAlphanum($self->{'theB'})){
          $self->_action(1);
        }
        else {
          $self->_action(2);
        }
      }
    }
    else {
      if ($self->{'theB'} eq ' '){
        if (isAlphanum($self->{'theA'})){
          $self->_action(1);
        }
        else {
          $self->_action(3);
        }
      }
      elsif ($self->{'theB'} eq "\n"){
        if ($list2{$self->{'theA'}}){
          $self->_action(1);
        }
        else {
          if (isAlphanum($self->{'theA'})){
            $self->_action(1);
          }
          else {
            $self->_action(3);
          }
        }
      }
      else {
        $self->_action(1);
      }
    }
  }
}

sub minify(){
  my $self = shift;
  my $instream = shift;
  my $outstream = shift;

  my $ref = \$instream;
  
  $self->{'indata'} = '';
  $self->{'indata_pos'} = 0;
  if (ref($ref) eq 'SCALAR' and $ref){
    $self->{'indata'} = $instream;
  }
  
  $self->{'data'} = '';
  $self->{'instream'} = $instream;
  $self->{'outstream'} = $outstream;
  $self->{'theA'} = 'None';
  $self->{'theB'} = 'None';
  $self->{'theLookahead'} = 'None';
  
  $self->_out("/* Compressed by the perl version of jsmin. */\n");
  $self->_out("/* ".__PACKAGE__." $VERSION */\n");
  
  $self->_jsmin();
  
  return $self->{'data'} || 1;
}

# For testing..
#package main;
#my $obj = new JavaScript::Minifier;
#$obj->minify(*STDIN, *STDOUT);


1;

=pod

=head1 NAME

JavaScript::Minifier - Perl translation of jsmin.c.

=head1 SYNOPSIS

  use JavaScript::Minifier;
  my $obj = new JavaScript::Minifier;
  $obj->minify(*STDIN, *STDOUT);
  
  use JavaScript::Minifier qw(jsmin);
  jsmin(*STDIN, *STDOUT);

=head1 DESCRIPTION

This work is a translation from C to Perl of jsmin.c published by
Douglas Crockford.  Permission is hereby granted to use the Perl
version under the same conditions as the jsmin.c on which it is
based.

Refer to the JSMin website for further information: 
http://javascript.crockford.com/jsmin.html

Speed is a bit slower than the python version and the python and perl
versions are quite a bit slower than the c version(of course).

Here are test results processing a 71K javascript file. This is
one of the largest we have -- most are considerably smaller.

               | wall clock seconds(approximate)
  ---------------------------------------
  Perl:        | 1.4
  Python:      | 1.0
  C:           | 0.03
  
  Tests performed on a Intel(R) Pentium(R) 4 CPU 1.80GHz under no load.

=head1 AUTHOR

Copyright (c) 2002 Douglas Crockford  (www.crockford.com)

Translated to Perl by: Eric Herrera, herrera at 10east dot com

=head1 COPYRIGHT

  Copyright (c) 2002 Douglas Crockford  (www.crockford.com)
   
  Permission is hereby granted, free of charge, to any person obtaining a copy of
  this software and associated documentation files (the "Software"), to deal in
  the Software without restriction, including without limitation the rights to
  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
  of the Software, and to permit persons to whom the Software is furnished to do
  so, subject to the following conditions:
   
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
   
  The Software shall be used for Good, not Evil.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.

=cut

