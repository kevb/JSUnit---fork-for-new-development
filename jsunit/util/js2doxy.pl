#!/bin/perl

# JsUnit - a JUnit port for JavaScript
# Copyright (C) 1999,2000,2001,2002 Joerg Schaible
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation in version 2 of the License.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# 
# Test suites built with JsUnit are derivative works derived from tested 
# classes and functions in their production; they are not affected by this 
# license.

use strict;

use vars qw( $VERSION );
$VERSION = "2.0";

############ Options ####################

use vars qw( $DEB_NONE $DEB_PARSER $DEB_SCANNER $DEB_DATABASE $DEB_DUMP $file );
$DEB_NONE = 0;
$DEB_DUMP = 1;
$DEB_DATABASE = 2;
$DEB_PARSER = 4;
$DEB_SCANNER = 8;

use Getopt::Long;
use Pod::Usage;
my ( $opt_usage, $opt_help, $opt_version, $opt_debug );
$opt_debug = 0;
Getopt::Long::Configure( "no_ignore_case" );
Getopt::Long::GetOptions(
	'questionmark|?' => \$opt_usage,
	'debug:i' => \$opt_debug,
	'help' => \$opt_help,
	'version' => \$opt_version );

print( "Version: $VERSION\n" ) and exit( 0 ) if( $opt_version );
pod2usage( -exitval => 0, -verbose => 2 ) if( $opt_help );
pod2usage( 1 ) if( $opt_usage or ( $#ARGV < 0 && -t ));


############ Error functions ############

sub syntax_err
{
	sub dump_struct;
	
	print( STDERR "Line $.: Syntax: @_\n" ); 
	dump_struct( $file, "FILE." ) if( $opt_debug & $DEB_DUMP );
	exit( 3 );
}

sub warning
{
	print( STDERR "Line $.: Warning: @_\n" );
}


############ Scanner ####################

use vars qw( @scan_mode_names $scan_mode $string_type );
use vars qw( $S_CODE $S_COMMENT $S_DOC_COMMENT $S_LINE_COMMENT $S_STRING );
# general scanner modes
@scan_mode_names = qw( CODE COMMENT DOC_COMMENT LINE_COMMENT STRING );
$S_CODE = 0;
$S_COMMENT = 1;
$S_DOC_COMMENT = 2;
$S_LINE_COMMENT = 3;
$S_STRING = 4;
$scan_mode = $S_CODE;
$string_type = "";

use vars qw( $identifier $prototype $interface );
$identifier = "[a-zA-Z_]\\w*";

use vars qw( $cur_line @token_patterns $newline_pattern );
# lexer 
$cur_line = "";
# recognized tokens
@token_patterns =
(
	"\\\\.",
	"@.",
    quotemeta("/**"),
    quotemeta("/*!"),
    quotemeta("*/"),
    quotemeta("/*"),
    quotemeta("//"),
    "(?:0[xX])?\\d+",
    $identifier,
    "\\s+",
    ".",
);
$newline_pattern = "[\\n\\f]";

use subs qw( switch_scan_mode );

# get next Token according to the @token_patterns array. 
# Reads next line, if current line is completed.
sub next_token
{
	my ( $token, $token_pattern, $pattern );
	local $_;

	while( $cur_line eq "" )
	{
		$cur_line = <>;
		$cur_line =~ s/\r//g; # Bug of Perl 5.6.1 for Cygwin on text mounts
		return if eof;
	}
	
	if( $cur_line ne "" )
	{
		foreach $token_pattern( @token_patterns )
		{
			if( $cur_line =~ s/^($token_pattern)// )
			{
				$token = $1;
				$pattern = $token_pattern;
				last;
			}
		}
	
		switch_scan_mode( $token );
		if( $opt_debug & $DEB_SCANNER )
		{
			$_ = $token; 
			s/\n/\\n/go; 
			print( STDERR "Scanner: '$_' ~ '$pattern' "
				.$scan_mode_names[$scan_mode]."\n" );
		}
	}

	$token;
}

# get next Token according to the @token_patterns array,
# which is not white-space.
# Reads next line, if current line is completed.
sub next_none_ws_token
{
	my $token = next_token();
	$token = next_token() while( $token =~ /^\s+/ );
	$token;
}

sub skip_line
{
	while( next_token() !~ /^$newline_pattern/ ) {};
	next_token() while( $cur_line =~ /^$newline_pattern/ );
}
 
# handle $scan_mode properly
# recognize comments and strings
sub switch_scan_mode
{
	my $token = shift;

	if( $token ne "" )
	{
		# recognize the mode endings
		if(( $scan_mode == $S_COMMENT ) || ( $scan_mode == $S_DOC_COMMENT ))
		{
			$scan_mode = $S_CODE if( $token eq "*/" );
		}
		elsif( $scan_mode == $S_LINE_COMMENT )
		{
			$scan_mode = $S_CODE if( $token =~ /$newline_pattern/ );
		}
		elsif( $scan_mode == $S_STRING ) 
		{
			syntax_err( "Unterminated string literal." )
				if( $token =~ /$newline_pattern/ );
			if( $token eq $string_type )
			{
				$string_type = "";
				$scan_mode = $S_CODE;
			}
		}
		# recognize the mode startings
		elsif( $token eq "/*" )
		{
			$scan_mode = $S_COMMENT;
		}
		elsif( $token eq "/**" or $token eq "/*!" )
		{
			$scan_mode = $S_DOC_COMMENT;
		}
		elsif( $token eq "//" )
		{
			$scan_mode = $S_LINE_COMMENT;
		}
		elsif( $token =~ /[\'\"]/ )
		{
			$scan_mode = $S_STRING;
			$string_type = $&;
		}
	}
}


############ Parser #####################

use vars qw( $last_token $last_doc @object_type_names );
$last_token = "";
@object_type_names = qw( 
	FILE 
	VARIABLE
	FUNCTION 
	CLASS 
	INTERFACE 
	MEMBER_FUNCTION 
	MEMBER_VARIABLE 
	CONSTRUCTOR
);
$object_type_names[-1] = "UNDEF";
use vars qw(
	$OT_UNKNOWN
	$OT_FILE 
	$OT_VARIABLE 
	$OT_FUNCTION 
	$OT_CLASS 
	$OT_INTERFACE 
	$OT_MEMBERVAR 
	$OT_MEMBERFUNC 
	$OT_CONSTRUCTOR 
);
$OT_UNKNOWN = -1;
$OT_FILE = 0;
$OT_VARIABLE = 1;
$OT_FUNCTION = 2;
$OT_CLASS = 3;
$OT_INTERFACE = 4;
$OT_MEMBERVAR = 5;
$OT_MEMBERFUNC = 6;
$OT_CONSTRUCTOR = 7;

use subs qw( parse next_parser_token parse_interface );

sub parse_string
{
	my $token = shift;
	$token .= next_token() while( $scan_mode == $S_STRING );
	$token;
}

sub parse_comment
{
	my $token;
	$token = next_token() 
		while( $scan_mode == $S_COMMENT or $scan_mode == $S_LINE_COMMENT );
	$token;
}

sub parse_doc_comment
{
	my $token = "/**";
	my $doc = { text => "" };
	my $master_doc = $doc;
	local $_;

	sub parse_type
	{
		local $_;
		my $token;
		
		$_ = next_none_ws_token();
		if( /[\'\"]/ )
		{
			my $type = $_;
			my $string;
			while(( $token = next_token()) ne $type )
			{
				syntax_err( "Unterminated string literal." )
					if( $token =~ /$newline_pattern/ );
				$string .= $token;
			}
			$_ = $string;
		}
		elsif( /^$identifier$/ )
		{
			$_ = $_.$token while(( $token = next_token()) !~ /^\s+/ );
		}
		else
		{
			syntax_err( "Identifier or string literal expected" );
		}

		( $_, $token );
	}

	LOOP: while( $scan_mode == $S_DOC_COMMENT )
	{
		if( $token =~ /(?:\\|@)/ )
		{
			$_ = $token.next_token();
			
			if( not exists $doc->{otype} )
			{
				$doc->{otype} = $OT_FILE if( /^(?:\\|@)$identifier$/ );
				$doc->{otype} = $OT_FUNCTION if( /^(?:\\|@)fn$/ );
				$doc->{otype} = $OT_INTERFACE if( /^(?:\\|@)interface$/ );
				$doc->{otype} = $OT_CLASS if( /^(?:\\|@)class$/ );
				$doc->{otype} = $OT_VARIABLE if( /^(?:\\|@)var$/ );
				if( /^(?:\\|@)ctor$/ )
				{
					$doc->{text} =~ s/^(.+[\n]+)[^\n]+$/\1/s;
					$doc->{otype} = $OT_CONSTRUCTOR;
					skip_line();
					$token = next_token();
					next;
				}
			}
			else
			{
				/^(?:\\|@)type$/ && do
				{
					$doc->{text} =~ s/^(.+[\n]+)[^\n]+$/\1/s;
					( $doc->{rtype}, $token ) = parse_type();
					skip_line() if( $token !~ /^$newline_pattern/ );
					$token = next_token();
					next LOOP;
				};
				/^(\\|@)tparam$/ && do
				{
					my $comment = $1;
					my ( $type, $token ) = parse_type();
					syntax_err( "Missing identifier" )
						if( $token =~ /^$newline_pattern/ );
					my $param = next_none_ws_token();
					syntax_err( "Identifier expected" )
						if( $param !~ /^$identifier$/ );
					$doc->{args}{$param} = $type;
					$_ = $comment."param $param";
				};
				/^(?:\\|@)ctor$/ && do
				{
					$doc->{text} .= "*/\n";
					$doc->{ctor} = { text => "/**\n", otype => $OT_UNKNOWN };
					$doc = $doc->{ctor};
					skip_line();
					$token = next_token();
					next LOOP;
				};
			}
			
			$doc->{text} .= $_;
		}
		else
		{
			$doc->{otype} = $OT_UNKNOWN
				if(     not exists $doc->{otype} 
					and $token =~ /^$identifier$/ );
			$doc->{text} .= $token;
		}
	
		$token = next_token();
	}
	$doc->{text} .= "*/\n";
	print( STDERR "Parser: Document for type "
			.$object_type_names[$doc->{otype}]."\n" )
		if( $opt_debug & $DEB_PARSER );
	$last_doc = $master_doc;
}

sub parse_code
{
	my $token; 
	while(( $token = $last_token ? $last_token : next_none_ws_token()) ne "" )
	{
		$last_token = undef;

		syntax_err( "Unexpected documentation comment." )
			if( $scan_mode == $S_DOC_COMMENT );

		parse_comment(), next
			if( $scan_mode == $S_COMMENT or $scan_mode == $S_LINE_COMMENT );

		last;
	}
	print( STDERR "Parser: '$token' ".$scan_mode_names[$scan_mode]."\n" )
		if( $opt_debug & $DEB_PARSER );
	$token;
}

sub next_parser_token
{
	my $token;
	my $struct = "";

	while(( $token = $last_token ? $last_token : next_none_ws_token()) ne "" )
	{
		$last_token = "";

		parse_comment(), next
			if( $scan_mode == $S_COMMENT or $scan_mode == $S_LINE_COMMENT );

		if( $scan_mode == $S_CODE )
		{
			if( $token =~ /^$identifier$/ )
			{
				my $debug = $opt_debug;
				$opt_debug &= ~$DEB_PARSER;
				
				$struct .= $token;
				while(( $token = parse_code()) eq "." )
				{
					$struct .= $token;
					$token = parse_code();
					syntax_err( "Identifier expected" )
						if( $token !~ /^$identifier$/ );
					$struct .= $token;
				}
				$last_token = $token if( not $last_token );
				$token = $struct;

				$opt_debug = $debug;
			}
			last;
		}
		elsif( $scan_mode == $S_STRING )
		{
			$token = parse_string( $token );
			last;
		}
		elsif( $scan_mode == $S_DOC_COMMENT )
		{
			last;
		}
	}
	print( STDERR "Parser: '$token' ".$scan_mode_names[$scan_mode]."\n" )
		if( $opt_debug & $DEB_PARSER );
	$token;
}

sub parse_variable
{
	my $context = shift;
	my $token = parse_code();

	if( $context->{otype} == $OT_FILE )
	{
		syntax_err( "Variable name expected, found '$token'." )
			if( $token !~ /^$identifier$/ );

		$context->{objs}{$token} = 
		{ 
			name => $token,
			otype => $OT_VARIABLE, 
			scope => $context 
		};
		my $varContext = $context->{objs}{$token};
		print( STDERR "Database: Variable '$token'.\n" ) 
			if( $opt_debug & $DEB_DATABASE );
		if( $last_doc )
		{
			if( $last_doc->{otype} == $OT_UNKNOWN )
			{
				if( exists $varContext->{doc} )
				{
					warning( "Comment for '$token' already exists,"
						." ignoring new." );
				}
				else
				{
					$varContext->{doc} = $last_doc;
					print( STDERR "Database: Comment for "
							."variable '$token'.\n" ) 
						if( $opt_debug & $DEB_DATABASE );
				}
			}
		}
	}
	while(( $token = parse_code()) ne ";" ) {}
	$last_doc = undef;
	$token;
}

sub parse_function
{
	my $context = shift;
	
	my $name;
	my $token = parse_code();
	if( $token ne "(" )
	{
		syntax_err( "Function name expected, found '$token'." )
			if( $token !~ /^$identifier$/ );
		$name = $token;
		$token = parse_code();
	}
	else
	{
		$context->{anonymous} = 0 if( not exists $context->{anonymous} );
		$name = "?".($context->{anonymous}++);
	}

	$context->{objs}{$name} = 
	{ 
		name => $name,
		otype => $OT_FUNCTION, 
		scope => $context 
	};
	my $fnContext = $context->{objs}{$name};
	print( STDERR "Database: Added "
			.($name =~ /^\?/ ? "anonymous " : "")."function '$name'.\n" ) 
		if( $opt_debug & $DEB_DATABASE );
	if( $last_doc )
	{
		if( $last_doc->{otype} == $OT_UNKNOWN )
		{
			if( exists $fnContext->{doc} )
			{
				warning( "Comment for '$name' already exists, ignoring new." );
			}
			else
			{
				$fnContext->{doc} = $last_doc;
				print( STDERR "Database: Comment for function '$name'.\n" ) 
					if( $opt_debug & $DEB_DATABASE );
			}
		}
		if( $last_doc->{otype} == $OT_CONSTRUCTOR )
		{
			if( exists $fnContext->{ctor} )
			{
				warning( "Constructor comment for '$name'"
					." already exists, ignoring new." );
			}
			else
			{
				$fnContext->{ctor} = $last_doc;
				print( STDERR "Database: Comment for constructor '$name'.\n" ) 
					if( $opt_debug & $DEB_DATABASE );
			}
		}
		$last_doc = undef;
	}

	syntax_err( "'(' expected, found '$token'." ) if( $token ne "(" );
	$fnContext->{args} = [];
	while(( $token = parse_code()) ne ")" )
	{
		next if( $token eq "," );
		syntax_err( "Function parameter name expected, found '$token'." )
			if( $token !~ /^$identifier$/ );
		push( @{$fnContext->{args}}, { name => $token } );
	}

	syntax_err( "'{' expected, found '$token'." )
		if(( $token = parse_code ) ne "{" );
	$last_token = $token;
	parse( $fnContext );

	$name;
}

sub create_base
{
	my ( $context, $base ) = @_;
	my $scope = $context;
	while( $scope && not exists $scope->{objs}{$base} )
	{
		$context = $scope;
		$scope = $scope->{scope};
	}	
	if( not $scope )
	{
		$context->{objs}{$base} = 
		{ 
			name => $base,
			otype => $OT_CLASS, 
			scope => $context,
		};
		$scope = $context;
		print( STDERR "Database: Added missing base class '$base'.\n" ) 
			if( $opt_debug & $DEB_DATABASE );
	}
	return $scope;
}

sub parse_prototype
{
	my $context = shift;
	my $token;
	my $name;
	my $member;
	my $fnContext;
	local $_;
	
	$_ = shift;
	    s/^($identifier)\.prototype$//
	 or s/^($identifier)\.prototype\.(.*)$/\2/
	 or syntax_err( "No a valid identifier '$1' for prototype definition." );
	
	$name = $1;
	
	if(    not exists $context->{objs}{$name}
	   and exists $context->{members}{$name} )
	{
		syntax_err( "Wrong prototype assignment to '$name' of type "
				.$object_type_names[$context->{members}{$name}{otype}]."." )
			if( $context->{members}{$name}{otype} != $OT_MEMBERFUNC );
		$context->{objs}{$name} = $context->{members}{$name};
		delete $context->{members}{$name};
		$context->{objs}{$name}{otype} = $OT_CLASS;
		print( STDERR "Database: '$name' is a nested class.\n" ) 
			if( $opt_debug & $DEB_DATABASE );
	}
	if( exists $context->{objs}{$name} )
	{
		$fnContext = $context->{objs}{$name};
	}
	else
	{
		$fnContext = create_base( $context, $name );
		$fnContext = $fnContext->{objs}{$name};
	}
	$fnContext->{otype} = $OT_CLASS if( $fnContext->{otype} == $OT_FUNCTION );
	syntax_err( "Prototype assignment to invalid type '"
			.$object_type_names[$fnContext->{otype}]."'." )
		if(   $fnContext->{otype} != $OT_CLASS 
		   && $fnContext->{otype} != $OT_INTERFACE );
	print( STDERR "Database: '$name' is a class.\n" ) 
		if( $opt_debug & $DEB_DATABASE );

	/^.+\.prototype/ && do
		{
			parse_prototype( $fnContext, $_ );
			return;
		};
	/^.+\.fulfills$/ && do
		{
			parse_interface( $fnContext, $_ );
			return;
		};
	!/^$identifier$/ and $_ and do
		{
			warning( "Unknown code construction '$_'"
				." in prototype definition of '$name'." );
			while(( $token = parse_code()) ne ";" ) {}
			$last_doc = undef;
			return;
		};
	
	$member = $_;
	syntax_err( "Syntax error in prototype definition."
			." '=' expected, found '$token'" )
		if( parse_code() ne "=" );
			
	if( $member eq "" )
	{
		syntax_err( "'new' expected, found '$token'." ) 
			if( parse_code() ne "new" );
		syntax_err( "Identifier expected, found '$token'." ) 
			if( parse_code() !~ /^($identifier)$/ );
		my $base = $1;
		while(( $token = parse_code ) =~ /[()]/ ) {}
		syntax_err( "';' expected, found '$token'." ) if( $token ne ";" );
		
		my $scope = create_base( $context, $base );
		$fnContext->{base} = $scope->{objs}{$base};
		if( $last_doc )
		{
			if( exists $fnContext->{doc} )
			{
				warning( "Comment for '$name' already exists, ignoring new." );
			}
			else
			{
				$fnContext->{doc} = $last_doc;
				print( STDERR "Database: Comment for class '$name'.\n" ) 
					if( $opt_debug & $DEB_DATABASE );
			}
		}
		$last_doc = undef;
	}
	else
	{
		my $doc = $last_doc;
		$last_doc = undef;
		
		if(( $token = parse_code()) =~ /^$identifier$/ )
		{
			my $end = 1;
			if( $token eq "function" )
			{
				$token = parse_function( $context );
				$end = 0;
			}
			my $scope = $context;
			$scope = $scope->{scope} 
				while( $scope && not exists $scope->{objs}{$token} );
			if( not $scope )
			{
				warning( "'$token' is not defined." );
			}
			else
			{
				$scope = $context->{objs}{$token};
				$scope->{otype} = $OT_MEMBERFUNC 
					if( $scope->{otype} == $OT_FUNCTION );
				syntax_err( "$token is not a member." )
					if(   $scope->{otype} != $OT_MEMBERFUNC 
					   && $scope->{otype} != $OT_MEMBERVAR );
				print( STDERR "Database: '$member' is a member "
					   .(  $scope->{otype} == $OT_MEMBERFUNC 
						 ? "function" 
						 : "variable")." with global name '"
					   .$scope->{name}."'.\n" ) 
					if( $opt_debug & $DEB_DATABASE );
				$fnContext->{members}{$member} = $scope;
				syntax_err( "';' expected, found '$token'." )
					if( $end and parse_code() ne ";" );
			}
		}
		else
		{
			syntax_err( "'$member' already defined." )
				if( exists $fnContext->{members}{$member} );
			$fnContext->{members}{$member} = { otype => $OT_MEMBERVAR };
			print( STDERR "Database: Added member variable '$member'.\n" ) 
				if( $opt_debug & $DEB_DATABASE );
			while(( $token = parse_code()) ne ";" ) {}
		}
		
		if( $doc && exists $fnContext->{members}{$member})
		{
			if( exists $fnContext->{members}{$member}{doc} )
			{
				warning( "Comment for '$member' already exists,".
					" ignoring new." );
			}
			else
			{
				$fnContext->{members}{$member}{doc} = $doc;
				print( STDERR "Database: Comment for member '$member'.\n" ) 
					if( $opt_debug & $DEB_DATABASE );
			}
		}
	}
}

sub parse_interface
{
	my $context = shift;
	my $token;
	local $_;

	$_ = shift;
	  	/^($identifier)\.(fulfills|inherits)$/
	 or do
		{
			warning(( $2 eq "fulfills" ? "Interface" : "Inheritance")
				." definition '$_' not supported." );
			while(( $token = parse_code()) ne ";" ) {}
			$last_doc = undef;
			return;
		};
	
	my $name = $1;
	my $type = $2;
	
	if(( $token = parse_code()) ne "(" )
	{
		warning( "'(' expected, found '$token'." );
		return;
	}
	if( not exists $context->{objs}{$name} )
	{
		warning( "Prototype fulfillment or inheritance, "
			."but no constructor of $name." );
		return;
	}
	my $fnContext = $context->{objs}{$name};
	$fnContext->{$type} = {};
	while(( $token = parse_code()) ne ")" )
	{
		next if( $token eq "," );
		if( $token !~ /^$identifier$/ or $token =~ /^(?:new|delete)$/ )
		{
			warning(( $type eq "fulfills" ? "Interface" : "Class" )
				." name expected, found '$token'." );
			return;
		}
		
		my $scope = create_base( $context, $token );
		$scope = $scope->{objs}{$token};
		$scope->{otype} = $OT_INTERFACE 
			if( $type eq "fulfills" && $scope->{otype} == $OT_CLASS );
		syntax_err( "$token is a '"
				.$object_type_names[$scope->{otype}]."', but not a class." )
			if(   ( $type eq "fulfills" && $scope->{otype} != $OT_INTERFACE )
			   || ( $type eq "inherits" && $scope->{otype} != $OT_CLASS ));
		print( STDERR "Database: '$token' is an interface.\n" ) 
			if( $type eq "fulfills" && ( $opt_debug & $DEB_DATABASE ));
		
		$fnContext->{$type}{$token} = $scope;
		print( STDERR "Database: '$name' implements '$token'.\n" ) 
			if( $type eq "fulfills" && ( $opt_debug & $DEB_DATABASE ));
		print( STDERR "Database: '$name' is inherited by '$token'.\n" ) 
			if( $type eq "inherits" && ( $opt_debug & $DEB_DATABASE ));
	}
}

sub parse
{
	my $context = shift;
	my $level = 0;
	my $token;
	local $_;

	PARSE: while(( $token = next_parser_token()) ne "" )
	{
		if( $scan_mode == $S_CODE )
		{
			for( $token )
			{
				/^}$/ && do
				{
					delete $context->{objs};
					--$level == 0;
					$context->{objs} = pop( @{$context->{symbols}} );
					last PARSE if $context->{otype} != $OT_FILE;
				};
				/^{$/ && do
				{
					my $objs = $context->{objs};
					push( @{$context->{symbols}}, $objs );
					delete $context->{objs};
					foreach my $key ( keys %$objs )
					{
						$context->{objs}{$key} = $objs->{$key};
					}
					++$level;
				};
				/^var$/				&& parse_variable( $context );
				/^function$/		&& parse_function( $context );
				/^.+\.prototype/	&& parse_prototype( $context, $token );
				/^.+\.(?:fulfills|inherits)$/	
									&& parse_interface( $context, $token );
			}
		}
		elsif( $scan_mode == $S_DOC_COMMENT )
		{
			parse_doc_comment();
			if(   $last_doc->{otype} == $OT_FILE 
			   || $last_doc->{otype} == $OT_CLASS
			   || $last_doc->{otype} == $OT_INTERFACE
			   || $last_doc->{otype} == $OT_VARIABLE )
			{
				$file->{doc} = [] if( not exists $file->{doc} );
				push( @{$file->{doc}}, $last_doc->{text} );
				$last_doc = undef;
			}
		}
	}

	syntax_err( "Unbalanced '}' found." ) if( $level < 0 );
	syntax_err( "EOF found. '}' expected." ) 
		if( $level > 0 && $context->{otype} != $OT_FILE );
}


############ Debug #######################

sub dump_struct
{
	my ( $struct, $prefix ) = @_;

	sub dump_value
	{
		my ( $prefix, $value ) = @_;
		$value =~ s/\n/\\n/go;
		print( STDERR $prefix, "$value\n" );
	}
	
	$prefix =~ /^(.*)\.$/ || $prefix =~ /^(.*)$/;
	dump_value( $1.": ", $struct );
	
	if( ref $struct eq "HASH" )
	{
		KEY: foreach my $key ( keys %$struct )
		{
			my $value = $struct->{$key};
			if( $key =~ /^(?:scope|base)$/ )
			{
				$value .= " ==> ".
					(exists $value->{name} ? $value->{name} : "undef");
				dump_value( $prefix.$key.": ", $value );
				next;
			}
			for( ref $value )
			{
				/HASH/ 	&& dump_struct( $value, $prefix.$key."." ) && next KEY;
				/ARRAY/ && dump_struct( $value, $prefix.$key ) && next KEY;
				/.*/ 	&& dump_value( $prefix.$key.": ", $value ) && next KEY;
			}
		}
	}
	elsif( ref $struct eq "ARRAY" )
	{
		I: foreach my $i ( 0 .. $#$struct )
		{
			my $value = $struct->[$i];
			for( ref $value )
			{
				/HASH/	&& dump_struct( $value, $prefix."[$i]." ) && next I;
				/ARRAY/	&& dump_struct( $value, $prefix."[$i]" ) && next I;
				/.*/ 	&& dump_value( $prefix."[$i]: ", $value ) && next I;
			}
		}
	}
	1;
}

############ output #####################

my $indent = "\t";

sub generate_file_docs
{
	my $docs = shift;
	local $_;
	print( $docs->[$_]."\n" ) foreach ( 0 .. $#$docs );
}

sub generate_forward_classes
{
	my ( $objects, $pref ) = @_;
	local $_;
	for( keys %$objects )
	{
		next if( !/^$identifier$/ );
		print( $pref."class $_;\n" )
			if( $objects->{$_}{otype} == $OT_CLASS );
		print( $pref."interface $_;\n" )
			if( $objects->{$_}{otype} == $OT_INTERFACE );
	}
}

sub generate_function
{
	my ( $func, $name, $pref, $otype ) = @_;
	my $delim = "";
	my $rtype = "void";
	my $argtypes = undef;
	my $doc;
	my $ctor;
	
	return if( $name !~ /^$identifier$/ );
	$doc = $func->{doc} 
		if(    exists $func->{doc} 
		   and (   $func->{otype} == $OT_FUNCTION
				or $func->{otype} == $OT_MEMBERFUNC ));
	$ctor = $func->{ctor}
		if(    exists $func->{ctor} 
		   and (   $func->{otype} == $OT_CLASS
		   	    or $func->{otype} == $OT_INTERFACE ));
	$ctor = $func->{doc}{ctor} 
		if(    exists $func->{doc} 
		   and exists $func->{doc}{ctor} 
		   and (   $func->{otype} == $OT_CLASS
		   	    or $func->{otype} == $OT_INTERFACE ));
	if( $doc )
	{
		syntax_err( "Documentation for $name is not for a function." )
			if(    $doc->{otype} != $func->{otype}
			   and $doc->{otype} != $OT_UNKNOWN );
		print( "\n".$doc->{text} );
		$rtype = $doc->{rtype} if( exists $doc->{rtype} );
		$argtypes = $doc->{args} if( exists $doc->{args} );
	}
	if( $ctor )
	{
		syntax_err( "Documentation for $name is not for a constructor." )
			if(   $ctor->{otype} != $OT_CONSTRUCTOR
			   && $ctor->{otype} != $OT_UNKNOWN );
		print( "\n".$ctor->{text} );
		$rtype = $ctor->{rtype} if( exists $doc->{rtype} );
		$argtypes = $ctor->{args} if( exists $doc->{args} );
	}
	my $virtual = $otype == $OT_INTERFACE ? "virtual " : "";
	print( $pref.$virtual."$rtype $name(" );
	for my $arg( @{$func->{args}} )
	{
		my $argtype = ( $argtypes and exists $doc->{args}{$arg->{name}} )
			? $doc->{args}{$arg->{name}} : "void";
		print( $delim."$argtype ", $arg->{name} );
		$delim = ", ";
	}
	print( ") { ", $rtype eq "void" ? "" : "return ($rtype)0; ", "}\n" );
}

sub generate_variable
{
	my ( $var, $name, $pref ) = @_;
	return if( $name !~ /^$identifier$/ );
	my $rtype = "int";
	if( exists $var->{doc} )
	{
		syntax_err( "Documentation for $name is not for a variable." )
			if(   $var->{doc}{otype} != $var->{otype}
			   && $var->{doc}{otype} != $OT_UNKNOWN );
		print( "\n".$var->{doc}{text} );
		$rtype = $var->{doc}{rtype} if( exists $var->{doc}{rtype} );
	}
	print( $pref."$rtype $name;\n" );
}

sub generate_class
{
	my ( $context, $name, $pref ) = @_;
	my $delim = " : ";
	my $type = "class ";
	local $_;
	
	return if( $name !~ /^$identifier$/ );
	$type = "interface " if( $context->{otype} == $OT_INTERFACE );
	if( exists $context->{doc} )
	{
		syntax_err( "Documentation for $name is not for a $type." )
			if( 	$context->{doc}{otype} != $context->{otype}
				and $context->{doc}{otype} != $OT_UNKNOWN );
		print( "\n".$context->{doc}{text} );
	}
	print( $pref.$type.$name );
	if( exists $context->{base} )
	{
		print( $delim, "public ", $context->{base}{name} );
		$delim = ", ";
	}
	for my $class( keys %{$context->{inherits}} )
	{
		print( $delim, "public $class" );
		$delim = ", ";
	}
	for my $if( keys %{$context->{fulfills}} )
	{
		print( $delim, "public $if" );
		$delim = ", ";
	}
	print( "\n$pref"."{\n" );
	print( "$pref"."public:\n" );
	generate_forward_classes( $context->{objs}, $pref.$indent );
	for( keys %{$context->{objs}} )
	{
		my $obj = $context->{objs}{$_};
		generate_class( $obj, $_, $pref.$indent )
			if(   $obj->{otype} == $OT_CLASS 
			   || $obj->{otype} == $OT_INTERFACE );
	}
	generate_function( $context, $name, $pref.$indent, $context->{otype} );
	for( keys %{$context->{members}} )
	{
		my $member = $context->{members}{$_};
		generate_function( $member, $_, $pref.$indent, $context->{otype} )
			if( $member->{otype} == $OT_MEMBERFUNC );
		generate_variable( $member, $_, $pref.$indent )
			if( $member->{otype} == $OT_MEMBERVAR );
	}
	print( "$pref};\n\n" );
}

sub generate
{
	sub generate;
	local $_;

	my ( $context, $name, $pref ) = @_;
	for( $context->{otype} )
	{
		/^$OT_FILE$/ && do
			{
				print( "\n" );
				generate_file_docs( $context->{doc} )
					if( exists $context->{doc} );
				generate_forward_classes( $context->{objs}, "" );
				generate( $context->{objs}{$_}, $_, "" )
					for( keys %{$context->{objs}} );
				print( "\n" );
			};
		/^$OT_FUNCTION$/ && do
			{
				generate_function( $context, $name, $pref, $OT_FUNCTION );
			};
		/^(?:$OT_CLASS|$OT_INTERFACE)$/ && do
			{
				generate_class( $context, $name, $pref );
			};
		/^$OT_VARIABLE$/ && do
			{
				generate_variable( $context, $name, $pref );
			};
	}
}

############ Main #######################

use vars qw( $context );

$context = 
{ 
	name => $ARGV[0],
	otype => $OT_FILE,
	scope => undef
};
$file = $context;

parse( $context );
dump_struct( $context, "FILE." ) if( $opt_debug & $DEB_DUMP );
generate( $context );


############ Manual #####################

__END__

=head1 NAME

js2doxy - utility to convert JavaScript into something Doxygen can understand

=head1 SYNOPSIS

 js2doxy.pl < file.js > file.cpp
 js2doxy.pl [Options] file.js

 Options:

 -?		Print usage
 -d, --debug	Debug mode
 -h, --help	Show manual
 -v, --version	Print version

=head1 OPTIONS

=over 8

=item B<-?>

Prints the usage of the script.

=item B<--debug>

Prints internal states to the error stream.
States are triggered by single bits:

 Bit 0:	Dump (1)
 Bit 1:	Database (2)
 Bit 2:	Parser (4)
 Bit 3:	Scanner	(8)

=item B<--help>

Shows the manual pages of the script using perldoc.

=item B<--version>

Print the version of the utility and exits.

=back

=head1 DESCRIPTION

This program will read from standard input or from the given input file
and convert the input into pseudo C++ that can be understood by help 
generator Doxygen.
The program parses the JavaScript and tries to attach the correct 
documentation comments.
Any unattached comment is placed into file scope.

=head1 HELP COMMANDS

The program will accept some additional help commands to produce better C++:

=item B<\ctor>

This command starts the description of the constructor.
It can be placed within the documentation comment for a class. 
It may be used also as first command in such a comment.

=item B<\tparam TYPE PARAM>

This command sets the type of a parameter.
It is replaced in the documentation comment with the B<\param> command
(without the B<TYPE>). 
The program will use the type information in the generated C++ code.  
It may not be the first command in a documentation comment.

=item B<\type TYPE>

This command sets the type of a variable or the return type of a function.
It may not be the first command in a documentation comment.

=head1 LIMITATIONS

The program uses internally a has map for the database. 
Therefore the sequence of the identified elements is by chance and the
grouping commands of Doxygen are not supported.

The program is currently not able to handle nested JavaScript prototype
assignments, e.g.:

 x.prototype.y.prototype = new z();

=cut
