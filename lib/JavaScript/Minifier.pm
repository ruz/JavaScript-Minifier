package JavaScript::Minifier;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(minify);

our $VERSION = '1.05';

# -----------------------------------------------------------------------------

#return true if the character is allowed in identifier.
sub isAlphanum { return $_[0] =~ /[\w\$\\]/ || ord($_[0]) > 126 }

my %isSpace = map { $_ => 1 } (' ', "\t");
sub isSpace { return $isSpace{ $_[0] } }

my %isEndspace = map { $_ => 1 } ("\n", "\r", "\f");
sub isEndspace { return $isEndspace{ $_[0] } }

my %isWhitespace = (%isSpace, %isEndspace);
sub isWhitespace { return $isWhitespace{ $_[0] } }

# New line characters before or after these characters can be removed.
# Not + - / in this list because they require special care.
my %isInfix = map { $_ => 1 } (qw(; : = & % * < > ? |), ',', "\n");
sub isInfix { return $isInfix{ $_[0] } }

# New line characters after these characters can be removed.
my %isPrefix = ( %isInfix, map { $_ => 1 } ('{', '(', '[', '!') );
sub isPrefix { return $isPrefix{ $_[0] } }

# New line characters before these characters can removed.
my %isPostfix = ( %isInfix, map { $_ => 1 } ('}', ')', ']') );
sub isPostfix { return $isPostfix{ $_[0] } }

# -----------------------------------------------------------------------------

sub _get {
  my $s = shift;
  if ($s->{inputFile} ) {
    return getc($s->{input});
  }
  else {
    no warnings 'substr';
    return substr($s->{input}, $s->{inputPos}++, 1);
  }
}

sub _put {
  if (my $outfile = $_[0]->{outfile}) {
    print $outfile $_[1];
  }
  else {
    $_[0]->{output} .= $_[1];
  }
}

# -----------------------------------------------------------------------------

# print a
# move b to a
# move c to b
# move d to c
# new d
#
# i.e. print a and advance
sub action1 {
  my $s = shift;
  if (!$isWhitespace{$s->{buf}[0]}) {
    $s->{lastnws} = $s->{buf}[0];    
  }

  _put($s, $s->{last} = shift @{ $s->{buf} });
  push @{ $s->{buf} }, _get($s);
}

sub action1_nws {
  my $s = shift;
  _put($s, $s->{last} = $s->{lastnws} = shift @{ $s->{buf} });
  push @{ $s->{buf} }, _get($s);
}

# sneeky output $s->{buf}[0] for comments
sub action2 {
  my $s = shift;

  _put($s, shift @{ $s->{buf} });
  push @{ $s->{buf} }, _get($s);
}

# move b to a
# move c to b
# move d to c
# new d
#
# i.e. delete a
sub action3 {
  my $s = shift;

  shift @{ $s->{buf} };
  push @{ $s->{buf} }, _get($s);
}

# move c to b
# move d to c
# new d
#
# i.e. delete b
sub action4 {
  my $s = shift;
  $s->{buf}[1] = $s->{buf}[2];
  $s->{buf}[2] = $s->{buf}[3];
  $s->{buf}[3] = _get($s);
}

# -----------------------------------------------------------------------------

# put string and regexp literals
# when this sub is called, $s->{buf}[0] is on the opening delimiter character
sub putLiteral {
  my $s = shift;
  my $delimiter = $s->{buf}[0]; # ', " or /
  action1_nws($s);
  do {
    while (defined($s->{buf}[0]) && $s->{buf}[0] eq '\\') { # escape character only escapes only the next one character
      action1_nws($s);       
      action1_nws($s);       
    }
    action1($s);
  } until ($s->{last} eq $delimiter || !defined($s->{buf}[0]));
  if ($s->{last} ne $delimiter) { # ran off end of file before printing the closing delimiter
    die 'unterminated ' . ($delimiter eq '\'' ? 'single quoted string' : $delimiter eq '"' ? 'double quoted string' : 'regular expression') . ' literal, stopped';
  }
}

# -----------------------------------------------------------------------------

# If $s->{buf}[0] is a whitespace then collapse all following whitespace.
# If any of the whitespace is a new line then ensure $s->{buf}[0] is a new line
# when this function ends.
sub collapseWhitespace {
  my $s = shift;

  my $lead = shift @{ $s->{buf} };
  $lead = "\n" if $isEndspace{$lead};

  while ( defined($s->{buf}[0]) && $isWhitespace{$s->{buf}[0]} ) {
    $lead = "\n" if $isEndspace{$s->{buf}[0]};
    shift @{ $s->{buf} };
    push @{ $s->{buf} }, _get($s);
  }
  unshift @{ $s->{buf} }, $lead;
}

# Advance $s->{buf}[0] to non-whitespace or end of file.
# Doesn't print any of this whitespace.
sub skipWhitespace {
  my $s = shift;
  while (defined($s->{buf}[0]) && $isWhitespace{$s->{buf}[0]}) {
    action3($s);
  }
}

# Advance $s->{buf}[0] to non-whitespace or end of file
# If any of the whitespace is a new line then print one new line.
sub preserveEndspace {
  my $s = shift;
  collapseWhitespace($s) if defined($s->{buf}[0]) && $isWhitespace{$s->{buf}[0]};
  if (defined($s->{buf}[0]) && $isEndspace{$s->{buf}[0]} && defined($s->{buf}[1]) && !$isPostfix{$s->{buf}[1]} ) {
    action1($s);
  }
  skipWhitespace($s);
}

sub onWhitespaceConditionalComment {
  my $s = shift;
  return (defined($s->{buf}[0]) && $isWhitespace{$s->{buf}[0]} &&
          defined($s->{buf}[1]) && $s->{buf}[1] eq '/' &&
          defined($s->{buf}[2]) && ($s->{buf}[2] eq '/' || $s->{buf}[2] eq '*') &&
          defined($s->{buf}[3]) && $s->{buf}[3] eq '@');
}

# -----------------------------------------------------------------------------

sub minify {
  my %h = @_;
  # Immediately turn hash into a hash reference so that notation is the same in this function
  # as others. Easier refactoring.
  my $s = \%h; # hash reference for "state". This module is functional programming and the state is passed between functions.

  # determine if the the input is a string or a file handle.
  my $ref = \$s->{input};
  if (defined($ref) && ref($ref) eq 'SCALAR'){
    $s->{inputPos} = 0;
    $s->{inputFile} = 0;
  }
  else {
    $s->{inputFile} = 1;
  }

  # Determine if the output is to a string or a file.
  if (!defined($s->{outfile})) {
    $s->{output} = '';
  }

  # Print the copyright notice first
  if ($s->{copyright}) {
    _put($s, '/* ' . $s->{copyright} . ' */');
  }

  # Initialize the buffer.
  do {
    $s->{buf}[0] = _get($s);
  } while (defined($s->{buf}[0]) && $isWhitespace{$s->{buf}[0]});
  $s->{buf}[1] = _get($s);
  $s->{buf}[2] = _get($s);
  $s->{buf}[3] = _get($s);
  $s->{last} = undef; # assign for safety
  $s->{lastnws} = undef; # assign for safety

  # local variables
  my $ccFlag; # marks if a comment is an Internet Explorer conditional comment and should be printed to output

  while (defined($s->{buf}[0])) { # on this line $s->{buf}[0] should always be a non-whitespace character or undef (i.e. end of file)
    
    if ($isWhitespace{$s->{buf}[0]}) { # check that this program is running correctly
      die 'minifier bug: minify while loop starting with whitespace, stopped';
    }
    
    # Each branch handles trailing whitespace and ensures $s->{buf}[0] is on non-whitespace or undef when branch finishes
    if ($s->{buf}[0] eq '/') { # a division, comment, or regexp literal
      if (defined($s->{buf}[1]) && $s->{buf}[1] eq '/') { # slash-slash comment
        $ccFlag = defined($s->{buf}[2]) && $s->{buf}[2] eq '@'; # tests in IE7 show no space allowed between slashes and at symbol
        do {
          $ccFlag ? action2($s) : action3($s);
        } until (!defined($s->{buf}[0]) || $isEndspace{$s->{buf}[0]});
        if (defined($s->{buf}[0])) { # $s->{buf}[0] is a new line
          if ($ccFlag) {
            action1($s); # cannot use preserveEndspace($s) here because it might not print the new line
            skipWhitespace($s);
          }
          elsif (defined($s->{last}) && !$isEndspace{$s->{last}} && !$isPrefix{$s->{last}}) {
            preserveEndspace($s);
          }
          else {
            skipWhitespace($s);            
          }
        }
      }
      elsif (defined($s->{buf}[1]) && $s->{buf}[1] eq '*') { # slash-star comment
        $ccFlag = defined($s->{buf}[2]) && $s->{buf}[2] eq '@'; # test in IE7 shows no space allowed between star and at symbol
        do {
          $ccFlag ? action2($s) : action3($s);
        } until (!defined($s->{buf}[1]) || ($s->{buf}[0] eq '*' && $s->{buf}[1] eq '/'));
        if (defined($s->{buf}[1])) { # $s->{buf}[0] is asterisk and $s->{buf}[1] is foreslash
          if ($ccFlag) {
            action2($s); # the *
            action2($s); # the /
            # inside the conditional comment there may be a missing terminal semi-colon
            preserveEndspace($s);
          }
          else { # the comment is being removed
            action3($s); # the *
            $s->{buf}[0] = ' ';  # the /
            collapseWhitespace($s);
            if (defined($s->{last}) && defined($s->{buf}[1]) && 
                ((isAlphanum($s->{last}) && (isAlphanum($s->{buf}[1])||$s->{buf}[1] eq '.')) ||
                 ($s->{last} eq '+' && $s->{buf}[1] eq '+') || ($s->{last} eq '-' && $s->{buf}[1] eq '-'))) { # for a situation like 5-/**/-2 or a/**/a
              # When entering this block $s->{buf}[0] is whitespace.
              # The comment represented whitespace that cannot be removed. Therefore replace the now gone comment with a whitespace.
              action1($s);
            }
            elsif (defined($s->{last}) && !$isPrefix{$s->{last}}) {
              preserveEndspace($s);
            }
            else {
              skipWhitespace($s);
            }
          }
        }
        else {
          die 'unterminated comment, stopped';
        }
      }
      elsif (defined($s->{lastnws}) && ($s->{lastnws} eq ')' || $s->{lastnws} eq ']' ||
                                        $s->{lastnws} eq '.' || isAlphanum($s->{lastnws}))) { # division
        action1($s);
        collapseWhitespace($s) if defined($s->{buf}[0]) && $isWhitespace{$s->{buf}[0]};
        # don't want a division to become a slash-slash comment with following conditional comment
        onWhitespaceConditionalComment($s) ? action1($s) : preserveEndspace($s);
      }
      else { # regexp literal
        putLiteral($s);
        collapseWhitespace($s) if defined($s->{buf}[0]) && $isWhitespace{$s->{buf}[0]};
        # don't want closing delimiter to become a slash-slash comment with following conditional comment
        onWhitespaceConditionalComment($s) ? action1($s) : preserveEndspace($s);
      }
    }
    elsif ($s->{buf}[0] eq '\'' || $s->{buf}[0] eq '"' ) { # string literal
      putLiteral($s);
      preserveEndspace($s);
    }
    elsif ($s->{buf}[0] eq '+' || $s->{buf}[0] eq '-') { # careful with + + and - -
      action1_nws($s);
      if (defined($s->{buf}[0]) && $isWhitespace{$s->{buf}[0]}) {
        collapseWhitespace($s);
        (defined($s->{buf}[1]) && $s->{buf}[1] eq $s->{last}) ? action1($s) : preserveEndspace($s);
      }
    }
    elsif (isAlphanum($s->{buf}[0])) { # keyword, identifiers, numbers
      action1_nws($s);
      if (defined($s->{buf}[0]) && $isWhitespace{$s->{buf}[0]}) {
        collapseWhitespace($s);
        # if $s->{buf}[1] is '.' could be (12 .toString()) which is property invocation. If space removed becomes decimal point and error.
        (defined($s->{buf}[1]) && (isAlphanum($s->{buf}[1]) || $s->{buf}[1] eq '.')) ? action1($s) : preserveEndspace($s);
      }
    }
    elsif ($s->{buf}[0] eq ']' || $s->{buf}[0] eq '}' || $s->{buf}[0] eq ')') { # no need to be followed by space but maybe needs following new line
      action1_nws($s);
      preserveEndspace($s);
    }
    elsif ($s->{stripDebug} && $s->{buf}[0] eq ';' &&
           defined($s->{buf}[1]) && $s->{buf}[1] eq ';' &&
           defined($s->{buf}[2]) && $s->{buf}[2] eq ';') {
      action3($s); # delete one of the semi-colons
      $s->{buf}[0] = '/'; # replace the other two semi-colons
      $s->{buf}[1] = '/'; # so the remainder of line is removed
    }
    else { # anything else just prints and trailing whitespace discarded
      action1($s);
      skipWhitespace($s);
    }
  }
  
  if (!defined($s->{outfile})) {
    return $s->{output};
  }
  
} # minify()

# -----------------------------------------------------------------------------

1;
__END__


=head1 NAME

JavaScript::Minifier - Perl extension for minifying JavaScript code


=head1 SYNOPSIS

To minify a JavaScript file and have the output written directly to another file

  use JavaScript::Minifier qw(minify);
  open(INFILE, 'myScript.js') or die;
  open(OUTFILE, '>myScript-min.js') or die;
  minify(input => *INFILE, outfile => *OUTFILE);
  close(INFILE);
  close(OUTFILE);

To minify a JavaScript string literal. Note that by omitting the outfile parameter a the minified code is returned as a string.

  my minifiedJavaScript = minify(input => 'var x = 2;');
  
To include a copyright comment at the top of the minified code.

  minify(input => 'var x = 2;', copyright => 'BSD License');

To treat ';;;' as '//' so that debugging code can be removed. This is a common JavaScript convention for minification.

  minify(input => 'var x = 2;', stripDebug => 1);

The "input" parameter is manditory. The "output", "copyright", and "stripDebug" parameters are optional and can be used in any combination.


=head1 DESCRIPTION

This module removes unnecessary whitespace from JavaScript code. The primary requirement developing this module is to not break working code: if working JavaScript is in input then working JavaScript is output. It is ok if the input has missing semi-colons, snips like '++ +' or '12 .toString()', for example. Internet Explorer conditional comments are copied to the output but the code inside these comments will not be minified.

The ECMAScript specifications allow for many different whitespace characters: space, horizontal tab, vertical tab, new line, carriage return, form feed, and paragraph separator. This module understands all of these as whitespace except for vertical tab and paragraph separator. These two types of whitespace are not minimized.

For static JavaScript files, it is recommended that you minify during the build stage of web deployment. If you minify on-the-fly then it might be a good idea to cache the minified file. Minifying static files on-the-fly repeatedly is wasteful.


=head2 EXPORT

None by default.

Exportable on demand: minifiy()


=head1 SEE ALSO

This project is developed using an SVN repository. To check out the repository
svn co http://dev.michaux.ca/svn/random/JavaScript-Minifier

This module is inspired by Douglas Crockford's JSMin:
http://www.crockford.com/javascript/jsmin.html

You may also be interested in the CSS::Minifier module also available on CPAN.


=head1 AUTHORS

Peter Michaux, E<lt>petermichaux@gmail.comE<gt>
Eric Herrera, E<lt>herrera@10east.comE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Peter Michaux

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.
