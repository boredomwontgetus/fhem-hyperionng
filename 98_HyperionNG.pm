#####################################################################################
# $Id: 98_HyperionNG.pm 18415 2020-12-28 00:56:23Z WarLLe $
#
# Usage
# 
# define <name> HyperionNG <IP[:PORT]> [<TOKEN>]
#
#####################################################################################

package main;

use strict;
use warnings;

use Color;

use DevIo;
use JSON;
use SetExtensions;
use Blocking;

my %HyperionNG_sets =
(
#  "active"            => "noArg",
#  "addEffect"         => "textField",
  "clear"             => "textField",
  "clearall"          => "noArg",
  "dim"               => "slider,0,1,100",
  "dimDown"           => "textField",
  "dimUp"             => "textField",
#  "inactive"          => "noArg",
  "mode"              => "clearall,effect,off,rgb",
  "off"               => "noArg",
  "on"                => "noArg",
  "rgb"               => "colorpicker,RGB",
  "reopen"            => "noArg",
  "toggle"            => "noArg",
  "videomode"		  => "2D,3DSBS,3DTAB"
#  "toggleMode"        => "noArg",
#  "valueGainDown"     => "textField",
#  "valueGainUp"       => "textField"
);

my $Hyperion_requiredVersion    = "2.0.0";
# Tan for reply commands: 
# 0 = authroze_required
# 1 = login
# 2 = logout
# 3 = sysinfo
# 4 = serverinfo [ALL]
my $Hyperion_serverinfo         = {"command" => "serverinfo", "tan" => 4};
my $Hyperion_sysinfo            = {"command" => "sysinfo", "tan" => 3};
my $Hyperion_authorize_required = {"command" => "authorize", "subcommand" => "tokenRequired", "tan" => 0};
my $Hyperion_authorize_login    = {"command" => "authorize", "subcommand" => "login", "token" => "0", "tan" => 1};
my $Hyperion_authorize_logout   = {"command" => "authorize", "subcommand" => "logout", "tan" => 2};
my $HyperionNG_Origin			= "FHEM";
my $Hyperion_webCmd             = "rgb:effect:mode:dimDown:dimUp:on:off";
my $Hyperion_webCmd_config      = "rgb:effect:configFile:mode:dimDown:dimUp:on:off";
my $Hyperion_homebridgeMapping  = "On=state,subtype=TV.Licht,valueOn=/rgb.*/,cmdOff=off,cmdOn=mode+rgb ".
                                  "On=state,subtype=Umgebungslicht,valueOn=clearall,cmdOff=off,cmdOn=clearall ".
                                  "On=state,subtype=Effekt,valueOn=/effect.*/,cmdOff=off,cmdOn=mode+effect ";
                                  # "On=state,subtype=Knight.Rider,valueOn=/.*Knight_rider/,cmdOff=off,cmdOn=effect+Knight_rider " .
                                  # "On=configFile,subtype=Eingang.HDMI,valueOn=hyperion-hdmi,cmdOff=configFile+hyperion,cmdOn=configFile+hyperion-hdmi ";

sub HyperionNG_Initialize($)
{
  my ($hash) = @_;
  $hash->{AttrFn}     = "HyperionNG_Attr";
  $hash->{DefFn}      = "HyperionNG_Define";
  $hash->{GetFn}      = "HyperionNG_Get";
#  $hash->{NotifyFn}   = "HyperionNG_Notify";
  $hash->{ReadFn}     = "HyperionNG_Read";
  $hash->{SetFn}      = "HyperionNG_Set";
  $hash->{ReadyFn}	  = "HyperionNG_Ready";
  $hash->{UndefFn}    = "HyperionNG_Undef";
  $hash->{AttrList}   = "disable:1,0 ".
                        "disabledForIntervals ".
                        "hyperionDefaultDuration ".
                        "hyperionDefaultPriority ".
                        "hyperionDimStep ".
                        "hyperionGainStep ".
                        "hyperionToggleModes ".
                        "hyperionVersionCheck:0 ".
                        "queryAfterSet:0 ".
						"token ".
						"hyperionOriginName ".
                        $readingFnAttributes;
  FHEM_colorpickerInit();
}


sub HyperionNG_Define($$)
{
  my ($hash,$def) = @_;
  my @args = split " ",$def;
  return "Usage: define <name> HyperionNG <IP[:PORT]> [<TOKEN>]"
    if (@args < 3);
  my ($name,$type,$host,$token) = @args;
  
  $host .= ':19444' if(not $host =~ m/:\d+$/);
  if ($token) 
  {
	  if (!($token =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/))
	  {
		return "Invalid token.";
	  }
  }
  
  $hash->{NOTIFYDEV} = "global";
  $hash->{DeviceName} = $host;
  if ($init_done && !defined $hash->{OLDDEF})
  {
	if ($token)
	{
		$attr{$name}{token} = $token;
	}
    addToDevAttrList($name,"lightSceneParamsToSave") if (!grep /^lightSceneParamsToSave/,split(" ",$attr{"global"}{userattr}));
    addToDevAttrList($name,"homebridgeMapping:textField-long") if (!grep /^homebridgeMapping/,split(" ",$attr{"global"}{userattr}));
    $attr{$name}{alias} = "Ambilight";
    $attr{$name}{cmdIcon} = "on:general_an off:general_aus dimDown:dimdown dimUp:dimup";
    $attr{$name}{devStateIcon} = '{HyperionNG_devStateIcon($name)}';
    $attr{$name}{homebridgeMapping} = $Hyperion_homebridgeMapping;
    $attr{$name}{icon} = "light_led_stripe_rgb";
    $attr{$name}{lightSceneParamsToSave} = "state";
    $attr{$name}{room} = "Hyperion";
	$attr{$name}{hyperionOriginName} = $HyperionNG_Origin;
    $attr{$name}{webCmd} = $Hyperion_webCmd;
    $attr{$name}{widgetOverride} = "dimUp:noArg dimDown:noArg";
  }
  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
  DevIo_OpenDev($hash,0,"HyperionNG_Init","HyperionNG_Callback");
  
  return undef;
}

sub HyperionNG_Ready($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  # try to reopen the connection in case the connection is lost
  if (AttrVal($name,"disable",0) == 0) {
	return DevIo_OpenDev($hash, 1, "HyperionNG_Init", "HyperionNG_Callback");
  }
  else {
	return undef;
  }
}

sub HyperionNG_ReadEffects($$) {
	my ($hash,$obj)  = @_;
	my $name    = $hash->{NAME};
	# Return if no adjustment given
	#return if (!defined $obj);
	
	my $data = $obj;
	my $effects = $data ? $data : undef;
	my $effectList  = $effects ? join(",",map {"$_->{name}"} @{$effects}) : "";
	$effectList     =~ s/ /_/g;
	
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash,"effect",(split /,/,$effectList)[0]) if (!defined ReadingsVal($name,"effect",undef));
	readingsBulkUpdate($hash,".effects",$effectList);
	readingsEndUpdate($hash,1);
}

sub HyperionNG_ReadComponents($$) {
	my ($hash,$obj)  = @_;
	my $name    = $hash->{NAME};
	# Return if no adjustment given
	return if (!defined $obj);

	my $compstate;
        my $compname;

        my %onoffmap = (0 => "off", 1 => "on");
	
	my $data = $obj;
        print Dumper($data);
        if (ref($data) eq 'ARRAY') {
                 foreach my $e (@$data) {
                   print Dumper($e);
                   $compstate = $data->[0]->{enabled};
                   $compname = $data->[0]->{name};
                   readingsBeginUpdate($hash);
                   readingsBulkUpdate($hash,"component_$compname",$compstate);

                   readingsEndUpdate($hash,1);

                     if ($compname eq 'ALL') {
                       readingsBeginUpdate($hash);
                       readingsBulkUpdate($hash,"state",$onoffmap{$compstate});
                       readingsEndUpdate($hash,1);
                     }
                 }
        }
        elsif (ref($data) eq 'HASH') {
                 $compstate = $data->{enabled};
                 $compname = $data->{name};
                 readingsBeginUpdate($hash);
                 readingsBulkUpdate($hash,"component_$compname",$compstate);
                 readingsEndUpdate($hash,1);
                 if ($compname eq 'ALL') {
                   readingsBeginUpdate($hash);
                   readingsBulkUpdate($hash,"state",$onoffmap{$compstate});
                   readingsEndUpdate($hash,1);
                 }
        }


#	my $effects = $data ? $data : undef;
#	my $effectList  = $effects ? join(",",map {"$_->{name}"} @{$effects}) : "";
#	$effectList     =~ s/ /_/g;
	
}


sub HyperionNG_ReadTransform($$) {
	my ($hash,$obj)  = @_;
	my $name    = $hash->{NAME};
	# Return if no adjustment given
	return if (!defined $obj);
	
	my $data = $obj->[0];
	

    

	readingsBeginUpdate($hash);
	if (defined $data->{blacklevel}) {
		my $blacklevel = $data->{blacklevel} ? sprintf("%.2f",$data->{blacklevel}->[0]).",".sprintf("%.2f",$data->{blacklevel}->[1]).",".sprintf("%.2f",$data->{blacklevel}->[2]) : undef;
		readingsBulkUpdate($hash,"transform_blacklevel",$blacklevel);
	}
	if (defined $data->{gamma}) {
		my $gamma = $data->{gamma} ? sprintf("%.2f",$data->{gamma}->[0]).",".sprintf("%.2f",$data->{gamma}->[1]).",".sprintf("%.2f",$data->{gamma}->[2]) : undef;
		readingsBulkUpdate($hash,"transform_blacklevel",$gamma);
	}
	if (defined $data->{id}) {
		readingsBulkUpdate($hash,"transform_id",$data->{id});
	}
	if (defined $data->{luminanceGain}) {
		my $luminanceGain = defined $data->{luminanceGain} ? sprintf("%.2f",$data->{luminanceGain}) : undef;
		readingsBulkUpdate($hash,"transform_luminanceGain",$luminanceGain);
	}
	if (defined $data->{luminanceMinimum}) {
		my $luminanceMinimum = defined $data->{luminanceMinimum} ? sprintf("%.2f",$data->{luminanceMinimum}) : undef;
		readingsBulkUpdate($hash,"transform_luminanceMinimum",$luminanceMinimum);
	}
	if (defined $data->{saturationGain}) {
		my $saturationGain = defined $data->{saturationGain} ? sprintf("%.2f",$data->{saturationGain}) : undef;
		readingsBulkUpdate($hash,"transform_saturationGain",$saturationGain);
	}
	if (defined $data->{saturationLGain}) {
		my $saturationLGain = defined $data->{saturationLGain} ? sprintf("%.2f",$data->{saturationLGain}) : undef;
		readingsBulkUpdate($hash,"transform_saturationLGain",$saturationLGain);
	}
	if (defined $data->{threshold}) {
		my $threshold = $data->{threshold} ? sprintf("%.2f",$data->{threshold}->[0]).",".sprintf("%.2f",$data->{threshold}->[1]).",".sprintf("%.2f",$data->{threshold}->[2]) : undef;
		readingsBulkUpdate($hash,"transform_threshold",$threshold);
	}
	if (defined $data->{valueGain}) {
		my $valueGain = defined $data->{valueGain} ? sprintf("%.2f",$data->{valueGain}) : undef;
		readingsBulkUpdate($hash,"transform_valueGain",$valueGain);
	}
	if (defined $data->{whitelevel}) {
		my $whitelevel = $data->{whitelevel} ? sprintf("%.2f",$data->{whitelevel}->[0]).",".sprintf("%.2f",$data->{whitelevel}->[1]).",".sprintf("%.2f",$data->{whitelevel}->[2]) : undef;
		readingsBulkUpdate($hash,"transform_threshold",$whitelevel);
	}
	
	readingsEndUpdate($hash,1);
}

sub HyperionNG_ReadVideomode($$) {
	my ($hash,$obj)  = @_;
	my $name    = $hash->{NAME};
	# Return if no adjustment given
	return if (!defined $obj);
	
	my $data = $obj;
	
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash,"videomode",$data);
	readingsEndUpdate($hash,1);
}

sub HyperionNG_ReadActiveEffects($$) {
	my ($hash,$obj)  = @_;
	my $name    = $hash->{NAME};
	# Return if no activeEffect given
	return if (!defined $obj->[0]);
	
	my $data = $obj->[0];
	
	readingsBeginUpdate($hash);
	if (defined $data->{args}) {
		#my $args = $data->{args} ? JSON->new->convert_blessed->canonical->encode($data->{args}) : undef;
		#readingsBulkUpdate($hash,"activeEffect_args",$args);
		#readingsBulkUpdate($hash,"effectArgs",$args);
	}
	if (defined $data->{name}) {
	
		readingsBulkUpdate($hash,"activeEffect_name",$data->{name});
		
		my $effectname = $data->{name};
		$effectname =~ s/ /_/g;
		readingsBulkUpdate($hash,"effect",$effectname);
		readingsBulkUpdate($hash,"mode","effect");
		readingsBulkUpdate($hash,"mode_before_off","effect");
		readingsBulkUpdate($hash,"state","effect $effectname");
	}
	if (defined $data->{script}) {
		#readingsBulkUpdate($hash,"activeEffect_script",$data->{script});
	}
	if (defined $data->{timeout}) {
		readingsBulkUpdate($hash,"activeEffect_timeout",$data->{timeout});
	}
	readingsEndUpdate($hash,1);
}

sub HyperionNG_ReadActiveColor($$) {
	my ($hash,$obj)  = @_;
	my $name    = $hash->{NAME};
	# Return if no activeColor given
	return if (!defined $obj->[0]);
	
	my $data = $obj->[0];
	
	readingsBeginUpdate($hash);
	if (defined $data->{"HSL Value"}) {
		my $h = $data->{"HSL Value"}->[0];
		my $s = $data->{"HSL Value"}->[1];
		my $l = $data->{"HSL Value"}->[2];
		my $hsl = $data->{"HSL Value"} ? join(",",@{$data->{"HSL Value"}}) : undef;
		readingsBulkUpdate($hash,"activeColor_HSL",$hsl);
	}
	if (defined $data->{"RGB Value"}) {
		my $r = $data->{"RGB Value"}->[0];
		my $g = $data->{"RGB Value"}->[1];
		my $b = $data->{"RGB Value"}->[2];
		my $hex = lc(Color::rgb2hex($r,$g,$b));
		my ($h,$s,$v) = Color::rgb2hsv($r / 255,$g / 255,$b / 255);
		my $dim = int($v * 100);
		my $rgb = $data->{"RGB Value"} ? join(",",@{$data->{"RGB Value"}}) : undef;
		readingsBulkUpdate($hash,"activeColor_RGB",$rgb);
		readingsBulkUpdate($hash,"mode","rgb");
		readingsBulkUpdate($hash,"mode_before_off","rgb");
		readingsBulkUpdate($hash,"dim",$dim);
		readingsBulkUpdate($hash,"rgb",$hex);
		readingsBulkUpdate($hash,"state","rgb $hex");
	}
	readingsEndUpdate($hash,1);
}
	
sub HyperionNG_ReadAdjustment($$) {
	my ($hash,$obj)  = @_;
	my $name    = $hash->{NAME};
	# Return if no adjustment given
	return if (!defined $obj->[0]);
	
	my $data = $obj->[0];
	
	readingsBeginUpdate($hash);
	
	if (defined $data->{backlightColored}) {
		my $value;
		if ($data->{backlightColored}) {
			$value = "true";
		}else {
			$value = "false";
		}
		readingsBulkUpdate($hash,"backlightColored",$value);
	}
	if (defined $data->{backlightThreshold}) {
		readingsBulkUpdate($hash,"backlightThreshold",$data->{backlightThreshold});
	}
	if (defined $data->{blue}) {
		my $adjB = $data ? join(",",@{$data->{blue}}) : undef;
		readingsBulkUpdate($hash,"adjustBlue",$adjB);
	}
	if (defined $data->{brightness}) {
		readingsBulkUpdate($hash,"brightness",$data->{brightness});
	}
	if (defined $data->{brightnessCompensation}) {
		readingsBulkUpdate($hash,"brightnessCompensation",$data->{brightnessCompensation});
	}
	if (defined $data->{cyan}) {
		my $adjC = $data ? join(",",@{$data->{cyan}}) : undef;
		readingsBulkUpdate($hash,"adjustCyan",$adjC);
	}
	if (defined $data->{gammaBlue}) {
		readingsBulkUpdate($hash,"gammaBlue",$data->{gammaBlue});
	}
	if (defined $data->{gammaGreen}) {
		readingsBulkUpdate($hash,"gammaGreen",$data->{gammaGreen});
	}
	if (defined $data->{gammaRed}) {
		readingsBulkUpdate($hash,"gammaRed",$data->{gammaRed});
	}
	if (defined $data->{green}) {
		my $adjG = $data ? join(",",@{$data->{green}}) : undef;
		readingsBulkUpdate($hash,"adjustGreen",$adjG);
	}
	if (defined $data->{id}) {
		readingsBulkUpdate($hash,"adjustID",$data->{id});
	}
	if (defined $data->{magenta}) {
		my $adjM = $data ? join(",",@{$data->{magenta}}) : undef;
		readingsBulkUpdate($hash,"adjustMagenta",$adjM);
	}
	if (defined $data->{red}) {
		my $adjR = $data ? join(",",@{$data->{red}}) : undef;
		readingsBulkUpdate($hash,"adjustRed",$adjR);
	}
	if (defined $data->{white}) {
		my $adjW = $data ? join(",",@{$data->{white}}) : undef;
		readingsBulkUpdate($hash,"adjustWhite",$adjW);
	}
	if (defined $data->{yellow}) {
		my $adjY = $data ? join(",",@{$data->{yellow}}) : undef;
		readingsBulkUpdate($hash,"adjustYellow",$adjY);
	}
	readingsEndUpdate($hash,1);
}

sub HyperionNG_ReadPriorities($$) {
	my ($hash,$obj)  = @_;
	my $name    = $hash->{NAME};
	# Return if no adjustment given
	return if ((!defined $obj->{priorities}) && (!defined $obj->{priorities_autoselect}));
	
	readingsBeginUpdate($hash);
	if (defined $obj->{priorities}) {
		my $priorities = $obj->{priorities} ? $obj->{priorities} : undef;
		my $data;
		
		foreach (@{$priorities}) {
			if ($_->{visible} eq 1) {
				$data = $_;
			}
		}
		
		
		# my $data = $obj->{priorities}->[0];
		my $componentId = $data->{componentId};
		my $origin = $data->{origin};
		my $priority = $data->{priority};
		if (defined $data->{duration_ms}) {
			readingsBulkUpdate($hash,"source_duration_ms",$data->{duration_ms});
		}
		else {
			readingsBulkUpdate($hash,"source_duration_ms",-1);
		}
		if (defined $data->{owner}) {
			readingsBulkUpdate($hash,"source_owner",$data->{owner});
		}
		else {
			readingsBulkUpdate($hash,"source_owner","");
		}
		if (defined $data->{value}) {
			readingsBulkUpdate($hash,"source_value",$data->{value});
		}
		
		if ($componentId eq  "COLOR") {
			if (defined $data->{value}->{"HSL"}) {
				my $h = $data->{value}->{"HSL"}->[0];
				my $s = $data->{value}->{"HSL"}->[1];
				my $l = $data->{value}->{"HSL"}->[2];
				my $hsl = $data->{value}->{"HSL"} ? join(",",@{$data->{value}->{"HSL"}}) : undef;
				readingsBulkUpdate($hash,"activeColor_HSL",$hsl);
			}
			if (defined $data->{value}->{"RGB"}) {
				my $r = $data->{value}->{"RGB"}->[0];
				my $g = $data->{value}->{"RGB"}->[1];
				my $b = $data->{value}->{"RGB"}->[2];
				my $hex = lc(Color::rgb2hex($r,$g,$b));
				my ($h,$s,$v) = Color::rgb2hsv($r / 255,$g / 255,$b / 255);
				my $dim = int($v * 100);
				my $rgb = $data->{value}->{"RGB"} ? join(",",@{$data->{value}->{"RGB"}}) : undef;
				if (!($hex eq "000000")) {
					readingsBulkUpdate($hash,"activeColor_RGB",$rgb);
					readingsBulkUpdate($hash,"mode","rgb");
					readingsBulkUpdate($hash,"mode_before_off","rgb");
					readingsBulkUpdate($hash,"dim",$dim);
					readingsBulkUpdate($hash,"rgb",$hex);
					readingsBulkUpdate($hash,"state","rgb $hex");
					#readingsBulkUpdate($hash,"activeEffect_args","");
					readingsBulkUpdate($hash,"activeEffect_name","");
					#readingsBulkUpdate($hash,"activeEffect_script","");
					readingsBulkUpdate($hash,"activeEffect_timeout","");
				}
				else {
					readingsBulkUpdate($hash,"activeColor_RGB","");
					readingsBulkUpdate($hash,"mode","off");
					readingsBulkUpdate($hash,"state","off");
					#readingsBulkUpdate($hash,"activeEffect_args","");
					readingsBulkUpdate($hash,"activeEffect_name","");
					#readingsBulkUpdate($hash,"activeEffect_script","");
					readingsBulkUpdate($hash,"activeEffect_timeout","");
				}
			}
		}
		elsif ($componentId eq "EFFECT") {
				my $effectname = $data->{owner};
				$effectname =~ s/ /_/g;
				readingsBulkUpdate($hash,"activeColor_RGB","");
				readingsBulkUpdate($hash,"activeColor_HSL","");
				readingsBulkUpdate($hash,"mode","effect");
				readingsBulkUpdate($hash,"effect",$effectname);
				readingsBulkUpdate($hash,"mode_before_off","effect");
				readingsBulkUpdate($hash,"state","effect $effectname");
				#readingsBulkUpdate($hash,"activeEffect_args","");
				readingsBulkUpdate($hash,"activeEffect_name",$data->{owner});
				#readingsBulkUpdate($hash,"activeEffect_script","");
				if (defined $data->{duration_ms}) {
					readingsBulkUpdate($hash,"activeEffect_timeout",$data->{duration_ms});
				}
				else {
					readingsBulkUpdate($hash,"activeEffect_timeout",-1);
				}
		}
		elsif ($componentId eq "GRABBER") {
			#readingsBulkUpdate($hash,"activeEffect_args","");
			readingsBulkUpdate($hash,"activeEffect_name","");
			#readingsBulkUpdate($hash,"activeEffect_script","");
			readingsBulkUpdate($hash,"activeEffect_timeout","");
			readingsBulkUpdate($hash,"activeColor_RGB","");
			readingsBulkUpdate($hash,"activeColor_HSL","");
			readingsBulkUpdate($hash,"mode","clearall");
			readingsBulkUpdate($hash,"mode_before_off","clearall");
#			readingsBulkUpdate($hash,"state","clearall");
		}
		elsif ($componentId eq "IMAGE") {
			#readingsBulkUpdate($hash,"activeEffect_args","");
			readingsBulkUpdate($hash,"activeEffect_name","");
			#readingsBulkUpdate($hash,"activeEffect_script","");
			readingsBulkUpdate($hash,"activeEffect_timeout","");
			readingsBulkUpdate($hash,"activeColor_RGB","");
			readingsBulkUpdate($hash,"activeColor_HSL","");
			readingsBulkUpdate($hash,"state","image");
		}
		
		
		readingsBulkUpdate($hash,"source_componentId",$componentId);
		readingsBulkUpdate($hash,"source_origin",$origin);
		readingsBulkUpdate($hash,"source",$priority);
	}
	if (defined $obj->{priorities_autoselect}) {
		my $value;
		if ($obj->{priorities_autoselect} eq 1) {
			$value = "true";
		}
		else {
			$value = "false";
		}
		readingsBulkUpdate($hash,"autoselect",$value);
	}
	
	readingsEndUpdate($hash,1);
}

# called when data was received
sub HyperionNG_Read($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	  
	my $data = DevIo_SimpleRead($hash);
	return if(!defined($data)); # connection lost
	  
	my $buffer = $hash->{PARTIAL};
	  
	Log3 $name, 5, "HyperionNG ($name) - received $data (buffer contains: $buffer)";
	  
	# concat received data to $buffer
	$buffer .= $data;

	# as long as the buffer contains newlines (complete datagramm)
	while($buffer =~ m/[\r\n]/)
	{
		my $msg;
		
		# extract the complete message ($msg), everything else is assigned to $buffer
		($msg, $buffer) = split("\n", $buffer, 2);
		
		# remove trailing whitespaces
		chomp $msg;
		Log3 $name, 5, "HyperionNG ($name) - parse $msg)";
		$msg = decode_json($msg);
		my $obj = eval {$msg};
		
		# parse the extracted message
	    HyperionNG_ParseJson($hash, $obj);
	}

	# update $hash->{PARTIAL} with the current buffer content
	$hash->{PARTIAL} = $buffer; 
	
}

sub HyperionNG_Get($@)
{
  my ($hash,$name,$cmd) = @_;
  return if (IsDisabled($name) && $cmd ne "?");
  my $params =  "devStateIcon:noArg ".
                "serverinfo:noArg ".
                "sysinfo:noArg ";
  return "get $name needs one parameter: $params"
    if (!$cmd);
  if ($cmd eq "sysinfo")
  {
    HyperionNG_GetSysinfo($hash);
  }
  elsif ($cmd eq "devStateIcon")
  {
    return HyperionNG_devStateIcon($hash);
  }
  elsif ($cmd eq "serverinfo")
  {
    HyperionNG_GetServerinfo($hash);
  }
  else
  {
    return "Unknown argument $cmd for $name, choose one of $params";
  }
}

sub HyperionNG_GetServerinfo(@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return if (IsDisabled($name));
  if (!$hash->{FD})
  {
    DevIo_OpenDev($hash, 1, "HyperionNG_Init", "HyperionNG_Callback");
    return;
  }
  HyperionNG_Call($hash);
  return;
}

sub HyperionNG_GetSysinfo(@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my %obj;
  return if (IsDisabled($name));
  if (!$hash->{FD})
  {
    DevIo_OpenDev($hash, 1, "HyperionNG_Init", "HyperionNG_Callback");
    return;
  }
  $obj{command} = "sysinfo";
  $obj{tan} = 3;
  HyperionNG_Call($hash,\%obj);
  return;
}

sub HyperionNG_Set($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  return if (IsDisabled($name) && $cmd !~ /^(active|\?)$/);
  my $value = (defined($args[0])) ? $args[0] : undef;
  my $value1 = (defined($args[1])) ? $args[1] : undef;
  return "\"set $name\" needs at least one argument and maximum five arguments" if (@aa < 1 || @aa > 5);
  my $duration = defined $args[1] ? int $args[1] : AttrNum($name,"hyperionDefaultDuration",0);
  my $priority = defined $args[2] ? int $args[2] : AttrNum($name,"hyperionDefaultPriority",50);
  my %HyperionNG_sets_local = %HyperionNG_sets;
  $HyperionNG_sets_local{effect} = ReadingsVal($name,".effects","") if (ReadingsVal($name,".effects",""));
  $HyperionNG_sets_local{adjustRed} = "textField";
  $HyperionNG_sets_local{adjustGreen} = "textField";
  $HyperionNG_sets_local{adjustBlue} = "textField";
  $HyperionNG_sets_local{adjustCyan} = "textField";
  $HyperionNG_sets_local{adjustMagenta} = "textField";
  $HyperionNG_sets_local{adjustYellow} = "textField";
  $HyperionNG_sets_local{adjustWhite} = "textField";
  $HyperionNG_sets_local{gammaRed} = "slider,0,0.1,5,1";
  $HyperionNG_sets_local{gammaGreen} = "slider,0,0.1,5,1";
  $HyperionNG_sets_local{gammaBlue} = "slider,0,0.1,5,1";
  $HyperionNG_sets_local{brightnessCompensation} = "slider,0,1,100";
  $HyperionNG_sets_local{brightness} = "slider,0,1,100";
  $HyperionNG_sets_local{backlightThreshold} = "slider,0,1,100";
  $HyperionNG_sets_local{backlightColored} = "true,false";
  $HyperionNG_sets_local{adjustID} = "textField";
  $HyperionNG_sets_local{source} = "textField";
  $HyperionNG_sets_local{autoselect} = "true,false";
  my $params = join(" ",map {"$_:$HyperionNG_sets_local{$_}"} keys %HyperionNG_sets_local);
  my %obj;
  Log3 $name,4,"$name: HyperionNG_Set cmd: $cmd";
  Log3 $name,4,"$name: HyperionNG_Set value: $value" if ($value);
  Log3 $name,4,"$name: HyperionNG_Set duration: $duration, priority: $priority" if ($cmd =~ /^rgb|dim|dimUp|dimDown|effect$/);
  if ($cmd eq "rgb")
  {
    return "Value of $cmd has to be in RGB hex format like ffffff or 3F7D90"
      if ($value !~ /^[\dA-Fa-f]{6}$/);
    $value = lc $value;
    my ($r,$g,$b) = Color::hex2rgb($value);
	my ($h,$s,$v) = Color::rgb2hsv($r / 255,$g / 255,$b / 255);
    my $dim = int($v * 100);
    $obj{color} = [$r,$g,$b];
    $obj{command} = "color";
    $obj{priority} = $priority * 1;
    $obj{duration} = $duration * 1000 if ($duration > 0);
	$obj{tan} = 5;
	$obj{origin} = defined $args[3] ? int $args[3] : AttrVal($name,"hyperionOriginName","FHEM");
  }
  elsif ($cmd eq "effect")
  {
    return "Effect $value is not available in the effect list of $name!"
      if ($value !~ /^([\w-]+)$/ || index(ReadingsVal($name,".effects",""),$value) == -1);
	$value =~ s/_/ /g;
    my %ef = ("name" => $value);
    $obj{effect} = \%ef;
    $obj{command} = "effect";
    $obj{priority} = $priority * 1;
    $obj{duration} = $duration * 1000 if ($duration > 0);
	$obj{origin} = $HyperionNG_Origin;
	$obj{tan} = 5;
  }
  elsif ($cmd eq "clearall")
  {
    return "$cmd need no additional value of $value" if (defined $value);
    $obj{command} = "clear";
	$obj{priority} = -1;
	$obj{tan} = 5;
  }
  elsif ($cmd eq "clear")
  {
    return "Value of $cmd has to be between 0 and 65536 in steps of 1"
      if (defined $value && $value !~ /^(\d+)$/ || $1 > 65536);
    $obj{command} = $cmd;
    $value = defined $1 ? $1 : AttrVal($name,"hyperionDefaultPriority",50);
    $obj{priority} = $value*1;
	$obj{tan} = 5;
  }
  elsif ($cmd eq "off")
  {
    return "$cmd need no additional value of $value" if (defined $value);

    $obj{command}     = "componentstate";
    $obj{componentstate}{component} = "ALL";
    $obj{componentstate}{state} = \0;
  }
  elsif ($cmd eq "on")
  {
    return "$cmd need no additional value of $value" if (defined $value);

    $obj{command}     = "componentstate";
    $obj{componentstate}{component} = "ALL";
    $obj{componentstate}{state} = \1;

    #my $rmode     = ReadingsVal($name,"mode_before_off","rgb");
    #my $rrgb      = ReadingsVal($name,"rgb","");
    #my $reffect   = ReadingsVal($name,"effect","");
    #my ($r,$g,$b) = Color::hex2rgb($rrgb);
    #my $set       = "$rmode $rrgb";
    #$set          = "$rmode $reffect" if ($rmode eq "effect");
    #$set          = $rmode if ($rmode eq "clearall");
    #CommandSet(undef,"$name $set");
    #return;
  }
  elsif ($cmd eq "toggle")
  {
    return "$cmd need no additional value of $value" if (defined $value);
    my $state = Value($name);
    my $nstate = $state ne "off" ? "off" : "on";
    CommandSet(undef,"$name $nstate");
    return;
  }
  elsif ($cmd eq "mode")
  {
    return "The value of mode has to be rgb,effect,clearall,off" if ($value !~ /^(off|clearall|rgb|effect)$/);
    Log3 $name,4,"$name: cmd: $cmd, value: $value";
    my $rmode     = $value;
    my $rrgb      = ReadingsVal($name,"rgb","");
    my $reffect   = ReadingsVal($name,"effect","");
    my ($r,$g,$b) = Color::hex2rgb($rrgb);
    my $set       = "$rmode $rrgb";
    $set          = "$rmode $reffect" if ($rmode eq "effect");
    $set          = $rmode if ($rmode eq "clearall");
    $set          = $rmode if ($rmode eq "off");
    CommandSet(undef,"$name $set");
    return;
  }
  elsif ($cmd eq "dim")
  {
    return "Value of $cmd has to be between 1 and 100"
      if ($value !~ /^(\d+)$/ || $1 > 100 || $1 < 1);
    my $rgb = ReadingsVal($name,"rgb","ffffff");
    $value = $value + 1
      if ($cmd eq "dim" && $value < 100);
    $value = $value / 100;
    my ($r,$g,$b) = Color::hex2rgb($rgb);
    my ($h,$s,$v) = Color::rgb2hsv($r / 255,$g / 255,$b / 255);
    my ($rn,$gn,$bn);
    ($rn,$gn,$bn) = Color::hsv2rgb($h,$s,$value)
      if ($cmd eq "dim");
    $rn = int($rn * 255);
    $gn = int($gn * 255);
    $bn = int($bn * 255);
    $obj{color} = [$rn,$gn,$bn];
    $obj{command} = "color";
    $obj{priority} = $priority * 1;
    $obj{duration} = $duration * 1000
      if ($duration > 0);
	$obj{origin} = $HyperionNG_Origin;
	$obj{tan} = 5;
	my $dim = $value * 100;	
  }
  elsif ($cmd =~ /^(dimUp|dimDown)$/)
  {
    return "Value of $cmd has to be between 1 and 99"
      if (defined $value && ($value !~ /^(\d+)$/ || $1 > 99 || $1 < 1));
    my $dim = ReadingsVal($name,"dim",100);
    my $dimStep = $value ? $value : AttrVal($name,"hyperionDimStep",10);
    my $dimUp = ($dim + $dimStep < 100) ? $dim + $dimStep : 100;
    my $dimDown = ($dim - $dimStep > 0) ? $dim - $dimStep : 1;
    my $set = $cmd eq "dimUp" ? $dimUp : $dimDown;
    CommandSet(undef,"$name dim $set");
    return;
  }
  elsif ($cmd eq "reopen")
  {
    DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
	DevIo_OpenDev($hash, 1, "HyperionNG_Init", "HyperionNG_Callback");
    return;
  }
  elsif ($cmd eq "videomode")
  {
    return "The value of videomode has to be 2D,3DSBS,3DTAB" if ($value !~ /^(2D|3DSBS|3DTAB)$/);
    Log3 $name,4,"$name: cmd: $cmd, value: $value";
	$obj{command} = "videomode";
	$obj{videoMode} = $value;
	$obj{tan} = 5;
  }
  elsif ($cmd =~ /^(adjustRed|adjustGreen|adjustBlue|adjustCyan|adjustMagenta|adjustYellow|adjustWhite)$/)
  {
    return "Each of the three comma separated values of $cmd must be from 0 an 255 in steps of 1"
      if ($value !~ /^(\d{1,3})?,(\d{1,3})?,(\d{1,3})?$/ || $1 > 255 || $2 > 255 || $3 > 255);
    $cmd              = "red"   if ($cmd eq "adjustRed");
    $cmd              = "green" if ($cmd eq "adjustGreen");
    $cmd              = "blue"  if ($cmd eq "adjustBlue");
	$cmd              = "cyan"   if ($cmd eq "adjustCyan");
    $cmd              = "magenta" if ($cmd eq "adjustMagenta");
    $cmd              = "yellow"  if ($cmd eq "adjustYellow");
	$cmd              = "white"  if ($cmd eq "adjustWhite");
    my $arr           = HyperionNG_list2array($value,"%d");
    my %ar            = ($cmd => $arr);
    $obj{command}     = "adjustment";
    $obj{adjustment}  = \%ar;
	$obj{tan} = 5;
  }
  #elsif ($cmd =~ /^adjustID$/)
  #{
  #  my %ar            = ($cmd => $value);
  #  $obj{command}     = "adjustment";
  #  $obj{adjustment}  = \%ar;
	#$obj{tan} = 5;
  #}
  elsif ($cmd =~ /^(gammaRed|gammaGreen|gammaBlue)$/)
  {
    return "The comma separated value of $cmd must be from 0.0 to 5.0 in steps of 0.1"
      if ($value !~ /^((\d)\.(\d))$/ || $1 > 5);
	$value = $value * 1;
	my %ar            = ("id" => $value);
    $obj{command}     = "adjustment";
    $obj{adjustment}  = \%ar;
	$obj{tan} = 5;
  }
  elsif ($cmd eq "backlightColored")
  {
    return "The value of $cmd must be true or false"
      if ($value !~ /^(true|false)$/);
	my %ar;
	if ($value eq "true") {
		%ar            = ($cmd => \1);
	}
	else {
		%ar            = ($cmd => \0);
	}
	
    $obj{command}     = "adjustment";
    $obj{adjustment}  = \%ar;
	$obj{tan} = 5;
  }
  elsif ($cmd =~ /^(brightness|brightnessCompensation|backlightThreshold)$/)
  {
    return "The value of $cmd must be from 0 to 100 in steps of 1"
      if ($value > 100);
	$value = $value * 1;
	my %ar            = ($cmd => $value);
    $obj{command}     = "adjustment";
    $obj{adjustment}  = \%ar;
	$obj{tan} = 5;
  }
  elsif ($cmd eq "source")
  {
    return "The value of $cmd must be from 1 to 250"
      if (($value > 250) || ($value < 1));
	$value = $value * 1;
    $obj{command}     = "sourceselect";
    $obj{priority}  = $value;
	$obj{tan} = 5;
  }
  elsif ($cmd eq "autoselect")
  {
    return "The value of $cmd must be true or false"
      if ($value !~ /^(true|false)$/);
    $obj{command}     = "sourceselect";
	if ($value eq "true") {
		$value = \1;
	}
	else {
		$value = \0;
	}
    $obj{auto}  = $value;
	$obj{tan} = 5;
  }
  elsif ($cmd eq "component")
  {
    return "The value of $cmd must be <start|stop>"
      if ($value !~ /^(start|stop)$/);
    my $state;
    $state = \1 if ($value eq 'start');
    $state = \0 if ($value eq 'stop');
    
    $obj{command}     = "componentstate";
    $obj{componentstate}{component} = "ALL";
    $obj{componentstate}{state} = $state;
  }
  if (keys %obj)
  {
    Log3 $name,5,"$name: $cmd obj json: ".encode_json(\%obj);
    SetExtensionsCancel($hash);
    HyperionNG_Call($hash,\%obj);
    return;
  }
  return SetExtensions($hash,$params,$name,@aa);
}

sub HyperionNG_ParseJson($$)
{
	my ($hash,$obj) = @_;
	my $name = $hash->{NAME};
	
	
	if (defined $obj->{data}) # Subscription data
	{
		my $command = $obj->{command};
		my $data = $obj->{data};
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash,"debug","update");
		readingsEndUpdate($hash,1);
		if ($command eq "effects-update") {
			HyperionNG_ReadEffects($hash,$data->{effects});
		}
		if ($command eq "priorities-update") {
			HyperionNG_ReadPriorities($hash,$data);
		}
		if ($command eq "adjustment-update") {
			HyperionNG_ReadAdjustment($hash,$data);
		}
		if ($command eq "videomode-update") {
			HyperionNG_ReadVideomode($hash,$data->{videomode});
		}
		if ($command eq "components-update") {
			HyperionNG_ReadComponents($hash,$data);
		}
		
	}
	elsif (defined $obj->{info}) # serverInfo oder sysinfo data
	{
		my $data = $obj->{info};
		if ($obj->{command} eq "sysinfo") # sysinfo data
		{
			my $hyperion = $data->{hyperion};
			my $system = $data->{system};
			
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash,"debug","sysinfo");
			readingsBulkUpdate($hash,"hyperion_build",$hyperion->{build});
			readingsBulkUpdate($hash,"hyperion_gitremote",$hyperion->{gitremote});
			readingsBulkUpdate($hash,"hyperion_id",$hyperion->{id});
			readingsBulkUpdate($hash,"hyperion_readOnlyMode",$hyperion->{readOnlyMode});
			readingsBulkUpdate($hash,"hyperion_time",$hyperion->{time});
			readingsBulkUpdate($hash,"hyperion_version",$hyperion->{version});
			
			readingsBulkUpdate($hash,"system_architecture",$system->{architecture});
			readingsBulkUpdate($hash,"system_cpuHardware",$system->{cpuHardware});
			readingsBulkUpdate($hash,"system_cpuModelName",$system->{cpuModelName});
			readingsBulkUpdate($hash,"system_cpuModelType",$system->{cpuModelType});
			readingsBulkUpdate($hash,"system_cpuRevision",$system->{cpuRevision});
			readingsBulkUpdate($hash,"system_domainName",$system->{domainName});
			readingsBulkUpdate($hash,"system_hostName",$system->{hostName});
			readingsBulkUpdate($hash,"system_kernelType",$system->{kernelType});
			readingsBulkUpdate($hash,"system_kernelVersion",$system->{kernelVersion});
			readingsBulkUpdate($hash,"system_prettyName",$system->{prettyName});
			readingsBulkUpdate($hash,"system_productType",$system->{productType});
			readingsBulkUpdate($hash,"system_productVersion",$system->{productVersion});
			readingsBulkUpdate($hash,"system_pyVersion",$system->{pyVersion});
			readingsBulkUpdate($hash,"system_qtVersion",$system->{qtVersion});
			readingsBulkUpdate($hash,"system_wordSize",$system->{wordSize});
			readingsEndUpdate($hash,1);
			
		}
		if ($obj->{command} eq "serverinfo") # serverinfo data
		{
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash,"debug","serverinfo");
			readingsBulkUpdate($hash,"rgb","ffffff") if (!defined ReadingsVal($name,"rgb",undef));
			readingsEndUpdate($hash,1);
			HyperionNG_ReadComponents($hash,$data->{components});
			HyperionNG_ReadEffects($hash,$data->{effects});
			HyperionNG_ReadActiveEffects($hash,$data->{activeEffects});
			HyperionNG_ReadActiveColor($hash,$data->{activeLedColor});
			HyperionNG_ReadAdjustment($hash,$data->{adjustment});
			HyperionNG_ReadPriorities($hash,$data);
			HyperionNG_ReadTransform($hash,$data->{transform});
			HyperionNG_ReadVideomode($hash,$data->{videomode});
		}
	}     
	elsif ((defined($obj->{command})) && (defined($obj->{success}))) # set return data
	{
		if ($obj->{success})
		{
			readingsBeginUpdate($hash);
			if ($obj->{tan} == 1) # successful return of login
			{
				readingsBulkUpdate($hash,"loginState","success");
			}
			readingsBulkUpdate($hash,"serverResponse","success");
			readingsEndUpdate($hash,1);
		}
		else
		{
			readingsBeginUpdate($hash);
			if ($obj->{tan} == 1) # unsuccessful return of login
			{
				readingsBulkUpdate($hash,"loginState","not authorized");
				DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
			}
			if ($obj->{error} eq "No Authorization") {
				readingsBulkUpdate($hash,"loginState","not authorized");
				DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
			}
			readingsBulkUpdate($hash,"lastError",$obj->{error});
			readingsBulkUpdate($hash,"serverResponse","ERROR");
			readingsEndUpdate($hash,1);
		}
	}
	else # unknown Data
	{
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash,"lastError","unknown data received");
		readingsBulkUpdate($hash,"serverResponse","ERROR");
		readingsEndUpdate($hash,1);
	}
}

sub HyperionNG_Attr(@)
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash  = $defs{$name};
  my $err;
  if ($cmd eq "set")
  {
    if ($attr_name eq "hyperionDefaultPriority")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be a number between 2 and 99" if ($attr_value !~ /^(\d+)$/ || $1 <= 1 || $1 >= 100);
    }
	elsif ($attr_name  eq "hyperionDefaultDuration")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be a number between 0 and 65536." if ($attr_value !~ /^(\d+)$/ || $1 < 0 || $1 > 65536);
    }
    elsif ($attr_name eq "hyperionDimStep")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be between 1 and 50 in steps of 1, default is 5." if ($attr_value !~ /^(\d+)$/ || $1 < 1 || $1 > 50);
    }
    elsif ($attr_name eq "hyperionToggleModes")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be a comma separated list of available modes of clearall,rgb,effect,off. Each mode only once in the list." if ($attr_value !~ /^(clearall|rgb|effect|off),(clearall|rgb|effect|off)(,(clearall|rgb|effect|off)){0,2}$/);
    }
    elsif ($attr_name eq "hyperionVersionCheck")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Can only be value 0." if ($attr_value !~ /^0$/);
    }
    elsif ($attr_name eq "queryAfterSet")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be 0 if set, default is 1." if ($attr_value !~ /^0$/);
    }
    elsif ($attr_name eq "disable")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be 1 if set, default is 0." if ($attr_value !~ /^0|1$/);
      return $err if ($err);
      if ($attr_value == 1)
      {
        BlockingKill($hash->{helper}{RUNNING_PID}) if ($hash->{helper}{RUNNING_PID});
        DevIo_Disconnected($hash);
        readingsSingleUpdate($hash,"state","disabled",1);
      }
      else
      {
        DevIo_OpenDev($hash, 1, "HyperionNG_Init", "HyperionNG_Callback");
      }
    }
	elsif ($attr_name eq "token")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be a valid HyperionNG token." if ($attr_value !~ /^[a0-f9]{8}-[a0-f9]{4}-[a0-f9]{4}-[a0-f9]{4}-[a0-f9]{12}$/);
	  if ($attr_value =~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/) {
		  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
		  DevIo_OpenDev($hash, 1, "HyperionNG_Init", "HyperionNG_Callback");
	  }
    }
  }
  return $err ? $err : undef;
}

# will be executed upon successful connection establishment (see DevIo_OpenDev())
sub HyperionNG_Init($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $json;

  if (AttrVal($name,"token","0") eq "0") {
	# send a Sysinfo request to the device
	$json = encode_json({"command" => "sysinfo", "tan" => 3});
	DevIo_SimpleWrite($hash, $json, 2,1);
  }
  else
  {
	# send a Login and Sysinfo to the device
	my $token = AttrVal($name,"token","0");
	$json = encode_json({"command" => "authorize", "subcommand" => "login", "token" => "$token", "tan" => 1});
	DevIo_SimpleWrite($hash, $json, 2,1);
	$json = encode_json({"command" => "sysinfo", "tan" => 3});
	DevIo_SimpleWrite($hash, $json, 2,1);
  }
  
  $json = encode_json({"command" => "serverinfo","subscribe" => ["components-update","priorities-update","effects-update","adjustment-update","videomode-update"], "tan" => 4});
  DevIo_SimpleWrite($hash, $json, 2,1);
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"state","initialized");
  readingsEndUpdate($hash,1);
  return undef;
}

# will be executed if connection establishment fails (see DevIo_OpenDev())
sub HyperionNG_Callback($)
  {
    my ($hash,$error) = @_;
    if ($error)
    {
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,"lastError",$error);
      readingsBulkUpdate($hash,"serverResponse","ERROR");
      readingsBulkUpdate($hash,"state","ERROR");
      readingsEndUpdate($hash,1);
    }
    return undef;
  }
  
 sub HyperionNG_Undef($$)
{                     
  my ($hash,$name) = @_;
  BlockingKill($hash->{helper}{RUNNING_PID}) if ($hash->{helper}{RUNNING_PID});
  DevIo_CloseDev($hash);
  return;                  
}

sub HyperionNG_Call($;$)
{
  my ($hash,$obj) = @_;
  $obj = $obj ? $obj : $Hyperion_serverinfo;
  my $name = $hash->{NAME};
  my $json = encode_json($obj);
  return if (IsDisabled($name));
  Log3 $name,5,"$name: HyperionNG_Call: json object: $json";
  DevIo_SimpleWrite($hash,$json,2,1);
}

sub HyperionNG_list2array($$)
{
  my ($list,$round) = @_;
  my @arr;
  foreach my $part (split /,/,$list)
  {
    $part = sprintf($round,$part) * 1;
    push @arr,$part;
  }
  return \@arr;
}

sub HyperionNG_devStateIcon($;$)
{
  my ($hash,$state) = @_; 
  $hash = $defs{$hash} if (ref $hash ne "HASH");
  return if (!$hash);
  my $name = $hash->{NAME};
  my $rgb = ReadingsVal($name,"rgb","");
  my $dim = ReadingsVal($name,"dim",10);
  my $val = ReadingsVal($name,"state","off");
  my $mode = ReadingsVal($name,"mode","");
  my $ico = int($dim / 10) * 10 < 10 ? 10 : int($dim / 10) * 10;
  return ".*:off:on"
    if ($val =~ /^off|rgb\s000000$/);
  return ".*:light_exclamation"
    if (($val =~ /^(ERROR|disconnected)$/ && !$hash->{INTERVAL}) || ($val eq "ERROR" && $hash->{INTERVAL}));
  return ".*:file_image@#000000:off"
    if ($val eq "image");
  return ".*:light_light_dim_$ico@#".$rgb.":off"
    if ($val ne "off" && $mode eq "rgb");
  return ".*:scene_scene@#000000:off"
    if ($val ne "off" && $mode eq "effect");
  return ".*:it_television@#0000FF:off"
    if ($val ne "off" && $mode eq "clearall");
  return ".*:light_question";
}

1;
