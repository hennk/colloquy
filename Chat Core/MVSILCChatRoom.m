#import "MVSILCChatRoom.h"
#import "MVSILCChatUser.h"
#import "MVSILCChatConnection.h"

@implementation MVSILCChatRoom
- (id) initWithChannelEntry:(SilcChannelEntry) channelEntry andConnection:(MVSILCChatConnection *) connection {
	if( ( self = [self init] ) ) {
		_connection = connection; // prevent circular retain
		[self updateWithChannelEntry:channelEntry];
	}

	return self;
}

#pragma mark -

- (void) updateWithChannelEntry:(SilcChannelEntry) channelEntry {
	MVSILCChatConnection *connection = (MVSILCChatConnection *)[self connection];

	SilcLock( [connection _silcClient] );

	[_name release];
	_name = [[NSString allocWithZone:nil] initWithUTF8String:channelEntry -> channel_name];

	[_uniqueIdentifier release];
	unsigned char *identifier = silc_id_id2str( channelEntry -> id, SILC_ID_CHANNEL );
	unsigned len = silc_id_get_len( channelEntry -> id, SILC_ID_CHANNEL );
	_uniqueIdentifier = [[NSData allocWithZone:nil] initWithBytes:identifier length:len];

	_channelEntry = channelEntry;

	SilcUnlock( [connection _silcClient] );
}

#pragma mark -

- (unsigned long) supportedModes {
	return ( MVChatRoomPrivateMode | MVChatRoomSecretMode | MVChatRoomInviteOnlyMode | MVChatRoomNormalUsersSilencedMode | MVChatRoomOperatorsOnlySetTopicMode | MVChatRoomPassphraseToJoinMode | MVChatRoomLimitNumberOfMembersMode );
}

- (unsigned long) supportedMemberUserModes {
	return ( MVChatRoomMemberFounderMode | MVChatRoomMemberOperatorMode | MVChatRoomMemberQuietedMode );
}

- (NSString *) displayName {
	return [self name];
}

#pragma mark -

- (void) partWithReason:(NSAttributedString *) reason {
	if( ! [self isJoined] ) return;
	if( [reason length] ) [[self connection] sendRawMessageWithFormat:@"LEAVE %@ %@", [self name], reason];
	else [[self connection] sendRawMessageWithFormat:@"LEAVE %@", [self name]];
	[self _setDateParted:[NSDate date]];
}

#pragma mark -

- (void) setTopic:(NSAttributedString *) topic {
	NSParameterAssert( topic != nil );
	const char *msg = [MVSILCChatConnection _flattenedSILCStringForMessage:topic andChatFormat:[[self connection] outgoingChatFormat]];
	[[self connection] sendRawMessageWithFormat:@"TOPIC %@ %s", [self name], msg];
}

#pragma mark -

- (void) sendMessage:(NSAttributedString *) message withEncoding:(NSStringEncoding) encoding asAction:(BOOL) action {
	NSParameterAssert( message != nil );

	const char *msg = [MVSILCChatConnection _flattenedSILCStringForMessage:message andChatFormat:[[self connection] outgoingChatFormat]];
	SilcMessageFlags flags = SILC_MESSAGE_FLAG_UTF8;

	if( action ) flags |= SILC_MESSAGE_FLAG_ACTION;

	SilcLock( [[self connection] _silcClient] );

	SilcChannelEntry channel = silc_client_get_channel( [[self connection] _silcClient], [[self connection] _silcConn], (char *) [[self name] UTF8String] );

	if( ! channel) {
		SilcUnlock( [[self connection] _silcClient] );
		return;
	}

	silc_client_send_channel_message( [[self connection] _silcClient], [[self connection] _silcConn], channel, NULL, flags, (unsigned char *) msg, strlen( msg ), false );

	silc_schedule_wakeup( [[self connection] _silcClient] -> schedule );

	SilcUnlock( [[self connection] _silcClient] );
}

#pragma mark -

- (void) setMode:(MVChatRoomMode) mode withAttribute:(id) attribute {
	[super setMode:mode withAttribute:attribute];

	switch( mode ) {
	case MVChatRoomPrivateMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ +p", [self name]];
		break;
	case MVChatRoomSecretMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ +s", [self name]];
		break;
	case MVChatRoomInviteOnlyMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ +i", [self name]];
		break;
	case MVChatRoomNormalUsersSilencedMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ +m", [self name]];
		break;
	case MVChatRoomOperatorsOnlySetTopicMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ +t", [self name]];
		break;
	case MVChatRoomPassphraseToJoinMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ +k %@", [self name], attribute];
		break;
	case MVChatRoomLimitNumberOfMembersMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ +l %@", [self name], attribute];
	default:
		break;
	}
}

- (void) removeMode:(MVChatRoomMode) mode {
	[super removeMode:mode];

	switch( mode ) {
	case MVChatRoomPrivateMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ -p", [self name]];
		break;
	case MVChatRoomSecretMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ -s", [self name]];
		break;
	case MVChatRoomInviteOnlyMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ -i", [self name]];
		break;
	case MVChatRoomNormalUsersSilencedMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ -m", [self name]];
		break;
	case MVChatRoomOperatorsOnlySetTopicMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ -t", [self name]];
		break;
	case MVChatRoomPassphraseToJoinMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ -k *", [self name]];
		break;
	case MVChatRoomLimitNumberOfMembersMode:
		[[self connection] sendRawMessageWithFormat:@"CMODE %@ -l *", [self name]];
	default:
		break;
	}
}

#pragma mark -

- (void) setMode:(MVChatRoomMemberMode) mode forMemberUser:(MVChatUser *) user {
	[super setMode:mode forMemberUser:user];

	switch( mode ) {
	case MVChatRoomMemberOperatorMode:
		[self _setChannelUserMode:SILC_CHANNEL_UMODE_CHANOP forUser:user];
		break;
	case MVChatRoomMemberQuietedMode:
		[self _setChannelUserMode:SILC_CHANNEL_UMODE_QUIET forUser:user];
	default:
		break;
	}
}

- (void) removeMode:(MVChatRoomMemberMode) mode forMemberUser:(MVChatUser *) user {
	[super removeMode:mode forMemberUser:user];

	switch( mode ) {
	case MVChatRoomMemberOperatorMode:
		[self _removeChannelUserMode:SILC_CHANNEL_UMODE_CHANOP forUser:user];
		break;
	case MVChatRoomMemberQuietedMode:
		[self _removeChannelUserMode:SILC_CHANNEL_UMODE_QUIET forUser:user];
	default:
		break;
	}
}

#pragma mark -

- (void) kickOutMemberUser:(MVChatUser *) user forReason:(NSAttributedString *) reason {
	SilcBuffer roomBuffer, userBuffer;
	MVSILCChatUser *silcUser = (MVSILCChatUser *) user;

	roomBuffer = silc_id_payload_encode( [self _getChannelEntry] -> id, SILC_ID_CHANNEL );
	if( ! roomBuffer ) return;

	userBuffer = silc_id_payload_encode( [silcUser _getClientEntry] -> id, SILC_ID_CLIENT );
	if( ! userBuffer ) {
		silc_buffer_free( roomBuffer );
		return;
	}

	[super kickOutMemberUser:user forReason:reason];

	if( reason ) {
		const char *msg = [MVSILCChatConnection _flattenedSILCStringForMessage:reason andChatFormat:[[self connection] outgoingChatFormat]];

		silc_client_command_send( [[self connection] _silcClient], [[self connection] _silcConn], SILC_COMMAND_KICK, [[self connection] _silcConn] -> cmd_ident, 3,
									1, roomBuffer -> data, roomBuffer -> len,
									2, userBuffer -> data, userBuffer -> len,
									3, msg, strlen(msg) );
	} else {
		silc_client_command_send( [[self connection] _silcClient], [[self connection] _silcConn], SILC_COMMAND_KICK, [[self connection] _silcConn] -> cmd_ident, 2,
									1, roomBuffer -> data, roomBuffer -> len,
									2, userBuffer -> data, userBuffer -> len );
	}

	silc_schedule_wakeup( [[self connection] _silcClient] -> schedule );

	[[self connection] _silcConn] -> cmd_ident++;

	silc_buffer_free( roomBuffer );
	silc_buffer_free( userBuffer );
}

/*
- (void) addBanForUser:(MVChatUser *) user {
	[super addBanForUser:user];
	[[self connection] sendRawMessageWithFormat:@"MODE %@ +b %@!%@@%@", [self name], ( [user nickname] ? [user nickname] : @"*" ), ( [user username] ? [user username] : @"*" ), ( [user address] ? [user address] : @"*" )];
}

- (void) removeBanForUser:(MVChatUser *) user {
	[super removeBanForUser:user];
	[[self connection] sendRawMessageWithFormat:@"MODE %@ -b %@!%@@%@", [self name], ( [user nickname] ? [user nickname] : @"*" ), ( [user username] ? [user username] : @"*" ), ( [user address] ? [user address] : @"*" )];
}
*/

#pragma mark -

- (SilcChannelEntry) _getChannelEntry {
	return _channelEntry;
}

#pragma mark -

- (void) _silcSetChannelUserMode:(unsigned int) SilcMode forUser:(MVSILCChatUser *) user {
	SilcBuffer roomBuffer, userBuffer;
	unsigned char modebuf[4];

	roomBuffer = silc_id_payload_encode( [self _getChannelEntry] -> id, SILC_ID_CHANNEL );
	if( ! roomBuffer ) return;

	userBuffer = silc_id_payload_encode( [user _getClientEntry] -> id, SILC_ID_CLIENT );
	if( ! userBuffer ) {
		silc_buffer_free( roomBuffer );
		return;
	}

	SILC_PUT32_MSB( SilcMode, modebuf );

	silc_client_command_send( [[self connection] _silcClient], [[self connection] _silcConn], SILC_COMMAND_CUMODE, [[self connection] _silcConn] -> cmd_ident, 3,
								1, roomBuffer -> data, roomBuffer -> len,
								2, modebuf, 4,
								3, userBuffer -> data, userBuffer -> len);
	[[self connection] _silcConn] -> cmd_ident++;
	
	silc_schedule_wakeup( [[self connection] _silcClient] -> schedule );

	silc_buffer_free( roomBuffer );
	silc_buffer_free( userBuffer );
}

- (void) _setChannelUserMode:(unsigned int) SilcMode forUser:(MVChatUser *) user {
	SilcChannelUser chu;
	SilcUInt32 mode = 0;
	MVSILCChatUser *silcUser = (MVSILCChatUser *)user;

	chu = silc_client_on_channel( [self _getChannelEntry] , [silcUser _getClientEntry] );
	if ( chu )
		mode = chu -> mode;

	mode |= SilcMode;

	[self _silcSetChannelUserMode:mode forUser:silcUser];
}

- (void) _removeChannelUserMode:(unsigned int)SilcMode forUser:(MVChatUser *) user {
	SilcChannelUser chu;
	SilcUInt32 mode = 0;
	MVSILCChatUser *silcUser = (MVSILCChatUser *)user;

	chu = silc_client_on_channel( [self _getChannelEntry] , [silcUser _getClientEntry] );
	if ( chu )
		mode = chu -> mode;

	mode &= ~SilcMode;

	[self _silcSetChannelUserMode:mode forUser:silcUser];
}

@end