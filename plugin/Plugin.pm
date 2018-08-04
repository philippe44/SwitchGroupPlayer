package Plugins::SwitchGroupPlayer::Plugin;

# Plugin to allow playlists to be switch between players, turning on the new player and turning off the old player
# Relies on the new sync api in 7.3
#
# Released under GPLv2 license, Triode - triode1@btinternet.com, 2008, 2009
# Make it compatible with Group Player by calling [sync] request and not directly the controller's sync - philippe_44@outlook.com, 2018

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Strings qw(string);

my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.switchgroupplayer',
	'defaultLevel' => 'ERROR',
	'description' => 'PLUGIN_SWITCHGROUPPLAYER'
});

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin;

	Slim::Control::Request::addDispatch(['switchplayer_menu'], [ 1, 1, 0, \&cliMenu   ]);
	Slim::Control::Request::addDispatch(['switchplayer'],      [ 0, 0, 1, \&action ]);

	my @menu = ({
		stringToken    => 'PLUGIN_SWITCHPLAYER',
		id             => 'pluginSwitchPlayer',
		displayWhenOff => 0,
		window => { 
			'icon-id'  => $class->_pluginDataFor('icon'),
			titleStyle => 'album',
		},
		actions => {
			go => {
				cmd => [ 'switchplayer_menu' ],
			},
		},
	});

	Slim::Control::Jive::registerPluginMenu(\@menu, 'extras');
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $playing   = $client->isPlaying;
	my $dirString = string($playing ? 'PLUGIN_SWITCHPLAYER_TO' : 'PLUGIN_SWITCHPLAYER_FROM');

	my @menu;

	for my $other (Slim::Player::Client::clients()) {
		
		if ($other ne $client && ($playing || $other->isPlaying)) {

			push @menu, {
				name  => $dirString . ' ' . $other->name,
				value => $playing ? { to => $other->id, from => $client->id } : { to => $client->id, from => $other->id },
			};
		}
	}

	if (!scalar @menu) {

		push @menu, {
			name  => $playing ? '{PLUGIN_SWITCHPLAYER_NOPLAYERS_PLAYING}' : '{PLUGIN_SWITCHPLAYER_NOPLAYERS_NONPLAYING}',
			value => undef,
		};
	}

	my $action = sub {
		if ($_[1] && (my $params = $_[1]->{'value'})) {
			Slim::Control::Request::executeRequest(undef, ['switchplayer', "from:" . $params->{'from'}, "to:" . $params->{'to'}]);
		} else {
			$client->bumpRight;
		}
	};

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', {
		header  => '{PLUGIN_SWITCHPLAYER}',
		headerAddCount => 1,
		playing => $playing,
		listRef => \@menu,
		onPlay  => $action,
		onRight => $action,
		onAdd   => $action,
	});

	$client->modeParam( 'handledTransition', 1 );
}

sub cliMenu {
	my $request = shift;
	my $client = $request->client;

	my $playing   = $client->isPlaying;
	my $dirString = string($playing ? 'PLUGIN_SWITCHPLAYER_TO' : 'PLUGIN_SWITCHPLAYER_FROM');

	my @menu = ();

	for my $other (Slim::Player::Client::clients()) {
		
		if ($other ne $client && ($playing || $other->isPlaying)) {
			
			my $from = $playing ? $client->id : $other->id;
			my $to   = $playing ? $other-> id : $client->id;

			push @menu, {
				text => $dirString . ' ' . $other->name,
				actions => {
					go => {
						cmd => [ 'switchplayer' ],
						params => {
							from => $from,
							to   => $to,
							menu => 'switchplayer',
						},
					},
				},
				nextWindow => 'parent',	
			};
		}
	}

	if (!@menu) {
		push @menu, {
			text => $playing ? string('PLUGIN_SWITCHPLAYER_NOPLAYERS_PLAYING') : string('PLUGIN_SWITCHPLAYER_NOPLAYERS_NONPLAYING'),
		};
	}

	$request->addResult('count', scalar @menu);
	$request->addResult('offset', 0);

	my $cnt = 0;

	for my $item (@menu) {
		$request->setResultLoopHash('item_loop', $cnt++, $item);
	}

	$request->setStatusDone;
}

sub action {
	my $request = shift;
	my $from_id = $request->getParam('from');
	my $to_id   = $request->getParam('to');

	my $from = Slim::Player::Client::getClient($from_id) || return;
	my $to   = Slim::Player::Client::getClient($to_id)   || return;

	Slim::Control::Request::executeRequest($to, ['power', 1]) unless $to->power;
	Slim::Control::Request::executeRequest($from, ['sync', $to_id]);
	Slim::Control::Request::executeRequest($from, ['sync', '-']);
	
	Slim::Buttons::Common::setMode($to, 'playlist');

	$request->setStatusDone;
}

1;
