#import "JVChatWindowController.h"
#import "MVConnectionsController.h"
#import "JVSmartTranscriptPanel.h"
#import "JVChatController.h"
#import "JVChatRoomPanel.h"
#import "JVChatConsolePanel.h"
#import "JVChatRoomBrowser.h"
#import "JVDirectChatPanel.h"
#import "JVDetailCell.h"
#import "MVMenuButton.h"

NSString *JVToolbarToggleChatDrawerItemIdentifier = @"JVToolbarToggleChatDrawerItem";
NSString *JVChatViewPboardType = @"Colloquy Chat View v1.0 pasteboard type";

@interface NSToolbar (NSToolbarPrivate)
- (NSView *) _toolbarView;
@end

#pragma mark -

@interface NSWindow (NSWindowPrivate) // new Tiger private method
- (void) _setContentHasShadow:(BOOL) shadow;
@end

#pragma mark -

@interface JVChatWindowController (JVChatWindowControllerPrivate)
- (void) _claimMenuCommands;
- (void) _resignMenuCommands;
- (void) _refreshSelectionMenu;
- (void) _refreshWindow;
- (void) _refreshWindowTitle;
- (void) _refreshList;
- (void) _refreshPreferences;
- (void) _saveWindowFrame;
@end

#pragma mark -

@interface NSOutlineView (ASEntendedOutlineView)
- (void) redisplayItemEqualTo:(id) item;
@end

#pragma mark -

@implementation JVChatWindowController
- (id) init {
	return ( self = [self initWithWindowNibName:@"JVChatWindow"] );
}

- (id) initWithWindowNibName:(NSString *) windowNibName {
	if( ( self = [super initWithWindowNibName:windowNibName] ) ) {
		_views = [[NSMutableArray allocWithZone:nil] initWithCapacity:10];
		_settings = [[NSMutableDictionary allocWithZone:nil] initWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:[self userDefaultsPreferencesKey]]];
	}

	return self;
}

- (void) windowDidLoad {
	NSTableColumn *column = [chatViewsOutlineView outlineTableColumn];
	JVDetailCell *prototypeCell = [[JVDetailCell allocWithZone:nil] init];
	[prototypeCell setFont:[NSFont toolTipsFontOfSize:11.]];
	[column setDataCell:prototypeCell];
	[prototypeCell release];

	[chatViewsOutlineView setRefusesFirstResponder:YES];
	[chatViewsOutlineView setAutoresizesOutlineColumn:NO];
	[chatViewsOutlineView setDoubleAction:@selector( _doubleClickedListItem: )];
	[chatViewsOutlineView setAutoresizesOutlineColumn:YES];
	[chatViewsOutlineView registerForDraggedTypes:[NSArray arrayWithObjects:JVChatViewPboardType, NSFilenamesPboardType, nil]];
	[chatViewsOutlineView setMenu:[[[NSMenu allocWithZone:nil] initWithTitle:@""] autorelease]];

	[favoritesButton setMenu:[MVConnectionsController favoritesMenu]];

	[self setShouldCascadeWindows:NO];
	[self setWindowFrameAutosaveName:@""];

	[[self window] setDelegate:nil]; // so we don't act on the windowDidResize notification
	[[self window] setFrameUsingName:@"Chat Window"];

	NSRect frame = [[self window] frame];
	NSPoint point = [[self window] cascadeTopLeftFromPoint:NSMakePoint( NSMinX( frame ), NSMaxY( frame ) )];
	[[self window] setFrameTopLeftPoint:point];

	[[self window] setDelegate:self];

	[[self window] useOptimizedDrawing:YES];
	[[self window] setOpaque:NO]; // let us poke transparant holes in the window

	if( [[self window] respondsToSelector:@selector( _setContentHasShadow: )] )
		[[self window] _setContentHasShadow:NO]; // this is new in Tiger

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector( _refreshPreferences ) object:nil];
	[self _refreshPreferences];

	[self _refreshList];
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	if( [self isWindowLoaded] ) {
		[[self window] setDelegate:nil];
		[[[self window] toolbar] setDelegate:nil];
		[[self window] close];
	}

	[viewsDrawer setDelegate:nil];
	[chatViewsOutlineView setDelegate:nil];

	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController> controller = nil;
	while( ( controller = [enumerator nextObject] ) )
		[controller setWindowController:nil];

	[_activeViewController release];
	[_views release];
	[_identifier release];
	[_settings release];

	_activeViewController = nil;
	_views = nil;
	_identifier = nil;
	_settings = nil;
	_showDelayed = NO;

	[super dealloc];
}

#pragma mark -

- (BOOL) respondsToSelector:(SEL) selector {
	if( [_activeViewController respondsToSelector:selector] ) return YES;
	else return [super respondsToSelector:selector];
}

- (void) forwardInvocation:(NSInvocation *) invocation {
	if( [_activeViewController respondsToSelector:[invocation selector]] )
		[invocation invokeWithTarget:_activeViewController];
	else [super forwardInvocation:invocation];
}

- (NSMethodSignature *) methodSignatureForSelector:(SEL) selector {
	if( [_activeViewController respondsToSelector:selector] )
		return [(NSObject *)_activeViewController methodSignatureForSelector:selector];
	else return [super methodSignatureForSelector:selector];
}

#pragma mark -

- (NSString *) identifier {
	return _identifier;
}

- (void) setIdentifier:(NSString *) identifier {
	id old = _identifier;
	_identifier = [identifier copyWithZone:[self zone]];
	[old release];

	old = _settings;
	_settings = [[NSMutableDictionary allocWithZone:nil] initWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:[self userDefaultsPreferencesKey]]];
	[old release];

	if( [[self identifier] length] ) {
		[[self window] setDelegate:nil]; // so we don't act on the windowDidResize notification
		[[self window] setFrameUsingName:[NSString stringWithFormat:@"Chat Window %@", [self identifier]]];
		[[self window] setDelegate:self];
	}

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector( _refreshPreferences ) object:nil];
	[self performSelector:@selector( _refreshPreferences ) withObject:nil afterDelay:0.];
}

#pragma mark -

- (NSString *) userDefaultsPreferencesKey {
	if( [[self identifier] length] )
		return [NSString stringWithFormat:@"Chat Window %@ Settings", [self identifier]];
	return @"Chat Window Settings";
}

- (void) setPreference:(id) value forKey:(NSString *) key {
	NSParameterAssert( key != nil );
	NSParameterAssert( [key length] );

	if( value ) [_settings setObject:value forKey:key];
	else [_settings removeObjectForKey:key];

	if( [_settings count] ) [[NSUserDefaults standardUserDefaults] setObject:_settings forKey:[self userDefaultsPreferencesKey]];
	else [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self userDefaultsPreferencesKey]];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (id) preferenceForKey:(NSString *) key {
	NSParameterAssert( key != nil );
	NSParameterAssert( [key length] );
	return [_settings objectForKey:key];
}

#pragma mark -

- (void) showWindow:(id) sender {
	if( [_views count] ) {
		[[self window] makeKeyAndOrderFront:nil];
		_showDelayed = NO;
	} else _showDelayed = YES;
}

- (void) showChatViewController:(id <JVChatViewController>) controller {
	NSAssert1( [_views containsObject:controller], @"%@ is not a member of this window controller.", controller );

	[chatViewsOutlineView selectRow:[chatViewsOutlineView rowForItem:controller] byExtendingSelection:NO];
	[chatViewsOutlineView scrollRowToVisible:[chatViewsOutlineView rowForItem:controller]];

	[self _refreshList];
	[self _refreshWindow];
}

#pragma mark -

- (id <JVInspection>) objectToInspect {
	id item = [self selectedListItem];
	if( [item conformsToProtocol:@protocol( JVInspection )] ) return item;
	else return nil;
}

- (IBAction) getInfo:(id) sender {
	id item = [self selectedListItem];
	if( [item conformsToProtocol:@protocol( JVInspection )] ) {
		if( [[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSAlternateKeyMask )
			[JVInspectorController showInspector:sender];
		else [[JVInspectorController inspectorOfObject:item] show:sender];
	}
}

#pragma mark -

- (IBAction) joinRoom:(id) sender {
	[[JVChatRoomBrowser chatRoomBrowserForConnection:[_activeViewController connection]] showWindow:nil];
}

#pragma mark -

- (void) close {
	[[JVChatController defaultController] performSelector:@selector( disposeChatWindowController: ) withObject:self afterDelay:0.];
	[[self window] orderOut:nil];
	[super close];
}

- (IBAction) closeCurrentPanel:(id) sender {
	if( [[self allChatViewControllers] count] == 1 ) [[self window] performClose:sender];
	else [[JVChatController defaultController] disposeViewController:_activeViewController];
}

- (IBAction) detachCurrentPanel:(id) sender {
	[[JVChatController defaultController] detachViewController:_activeViewController];
}

- (IBAction) selectPreviousPanel:(id) sender {
	int currentIndex = [_views indexOfObject:_activeViewController];
	int index = 0;

	if( currentIndex - 1 >= 0 ) index = ( currentIndex - 1 );
	else index = ( [_views count] - 1 );

	[self showChatViewController:[_views objectAtIndex:index]];
}

- (IBAction) selectPreviousActivePanel:(id) sender {
	int currentIndex = [_views indexOfObject:_activeViewController];
	int index = currentIndex;
	BOOL done = NO;

	do {
		if( [[_views objectAtIndex:index] respondsToSelector:@selector( newMessagesWaiting )] && [[_views objectAtIndex:index] newMessagesWaiting] > 0 )
			done = YES;

		if( ! done ) {
			if( index == 0 ) index = [_views count] - 1;
			else index--;
		}
	} while( index != currentIndex && ! done );

	[self showChatViewController:[_views objectAtIndex:index]];
}

- (IBAction) selectNextPanel:(id) sender {
	unsigned currentIndex = [_views indexOfObject:_activeViewController];
	unsigned index = 0;

	if( currentIndex + 1 < [_views count] ) index = ( currentIndex + 1 );
	else index = 0;

	[self showChatViewController:[_views objectAtIndex:index]];
}

- (IBAction) selectNextActivePanel:(id) sender {
	unsigned currentIndex = [_views indexOfObject:_activeViewController];
	unsigned index = currentIndex;
	BOOL done = NO;

	do {
		if( [[_views objectAtIndex:index] respondsToSelector:@selector( newMessagesWaiting )] && [[_views objectAtIndex:index] newMessagesWaiting] > 0 )
			done = YES;

		if( ! done ) {
			if( index == [_views count] - 1 ) index = 0;
			else index++;
		}
	} while( index != currentIndex && ! done );

	[self showChatViewController:[_views objectAtIndex:index]];
}

#pragma mark -

- (id <JVChatViewController>) activeChatViewController {
	return _activeViewController;
}

- (id <JVChatListItem>) selectedListItem {
	long index = -1;
	if( ( index = [chatViewsOutlineView selectedRow] ) == -1 ) return nil;
	return [chatViewsOutlineView itemAtRow:index];
}

#pragma mark -

- (void) addChatViewController:(id <JVChatViewController>) controller {
	[self insertChatViewController:controller atIndex:[_views count]];
}

- (void) insertChatViewController:(id <JVChatViewController>) controller atIndex:(unsigned int) index {
	NSParameterAssert( controller != nil );
	NSAssert1( ! [_views containsObject:controller], @"%@ already added.", controller );
	NSAssert( index <= [_views count], @"Index is beyond bounds." );

	BOOL needShow = ( ! [_views count] );

	[_views insertObject:controller atIndex:index];
	[controller setWindowController:self];

	if( ! [[self identifier] length] && [_views count] == 1 ) {
		[[self window] setDelegate:nil]; // so we don't act on the windowDidResize notification
		[[self window] setFrameUsingName:[NSString stringWithFormat:@"Chat Window %@", [controller identifier]]];
		[[self window] setDelegate:self];
	}

	if( needShow && ! _showDelayed )
		[[self  window] orderWindow:NSWindowBelow relativeTo:[[[NSApplication sharedApplication] keyWindow] windowNumber]];

	if( _showDelayed ) [self showWindow:nil];

	[self _saveWindowFrame];
	[self _refreshList];
	[self _refreshWindow];

	if( [self isMemberOfClass:[JVChatWindowController class]] && [_views count] >= 2 ) {
		[chatViewsOutlineView scrollRowToVisible:[chatViewsOutlineView rowForItem:controller]];
		[viewsDrawer open];
	}
}

#pragma mark -

- (void) removeChatViewController:(id <JVChatViewController>) controller {
	NSParameterAssert( controller != nil );
	NSAssert1( [_views containsObject:controller], @"%@ is not a member of this window controller.", controller );

	if( _activeViewController == controller ) {
		[_activeViewController release];
		_activeViewController = nil;
	}

	[controller setWindowController:nil];
	[_views removeObjectIdenticalTo:controller];

	[self _refreshList];
	[self _refreshSelectionMenu];
	[self _refreshWindow];

	if( ! [_views count] && [[self window] isVisible] )
		[self close];
}

- (void) removeChatViewControllerAtIndex:(unsigned int) index {
	NSAssert( index <= [_views count], @"Index is beyond bounds." );
	[self removeChatViewController:[_views objectAtIndex:index]];
}

- (void) removeAllChatViewControllers {
	[_activeViewController release];
	_activeViewController = nil;

	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController> controller = nil;

	while( ( controller = [enumerator nextObject] ) )
		[controller setWindowController:nil];

	[_views removeAllObjects];

	[self _refreshList];
	[self _refreshWindow];

	if( [[self window] isVisible] )
		[self close];
}

#pragma mark -

- (void) replaceChatViewController:(id <JVChatViewController>) controller withController:(id <JVChatViewController>) newController {
	NSParameterAssert( controller != nil );
	NSParameterAssert( newController != nil );
	NSAssert1( [_views containsObject:controller], @"%@ is not a member of this window controller.", controller );
	NSAssert1( ! [_views containsObject:newController], @"%@ is already a member of this window controller.", newController );

	[self replaceChatViewControllerAtIndex:[_views indexOfObjectIdenticalTo:controller] withController:newController];
}

- (void) replaceChatViewControllerAtIndex:(unsigned int) index withController:(id <JVChatViewController>) controller {
	NSParameterAssert( controller != nil );
	NSAssert1( ! [_views containsObject:controller], @"%@ is already a member of this window controller.", controller );
	NSAssert( index <= [_views count], @"Index is beyond bounds." );

	id <JVChatViewController> oldController = [_views objectAtIndex:index];

	if( _activeViewController == oldController ) {
		[_activeViewController release];
		_activeViewController = nil;
	}

	[oldController setWindowController:nil];
	[_views replaceObjectAtIndex:index withObject:controller];
	[controller setWindowController:self];

	[self _saveWindowFrame];
	[self _refreshList];
	[self _refreshWindow];
}

#pragma mark -

- (NSArray *) chatViewControllersForConnection:(MVChatConnection *) connection {
	NSParameterAssert( connection != nil );

	NSMutableArray *ret = [NSMutableArray array];
	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController> controller = nil;

	while( ( controller = [enumerator nextObject] ) )
		if( [controller connection] == connection )
			[ret addObject:controller];

	return ret;
}

- (NSArray *) chatViewControllersWithControllerClass:(Class) class {
	NSParameterAssert( class != NULL );
	NSAssert( [class conformsToProtocol:@protocol( JVChatViewController )], @"The tab controller class must conform to the JVChatViewController protocol." );

	NSMutableArray *ret = [NSMutableArray array];
	NSEnumerator *enumerator = [_views objectEnumerator];
	id <JVChatViewController> controller = nil;

	while( ( controller = [enumerator nextObject] ) )
		if( [controller isMemberOfClass:class] )
			[ret addObject:controller];

	return ret;
}

- (NSArray *) allChatViewControllers {
	return [NSArray arrayWithArray:_views];
}

#pragma mark -

- (NSToolbarItem *) toggleChatDrawerToolbarItem {
	NSToolbarItem *toolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:JVToolbarToggleChatDrawerItemIdentifier];

	[toolbarItem setLabel:NSLocalizedString( @"Drawer", "chat panes drawer toolbar item name" )];
	[toolbarItem setPaletteLabel:NSLocalizedString( @"Panel Drawer", "chat panes drawer toolbar customize palette name" )];

	[toolbarItem setToolTip:NSLocalizedString( @"Toggle Chat Panel Drawer", "chat panes drawer toolbar item tooltip" )];
	[toolbarItem setImage:[NSImage imageNamed:@"showdrawer"]];

	[toolbarItem setTarget:self];
	[toolbarItem setAction:@selector( toggleViewsDrawer: )];

	return [toolbarItem autorelease];
}

- (IBAction) toggleViewsDrawer:(id) sender {
	if( [viewsDrawer state] == NSDrawerClosedState || [viewsDrawer state] == NSDrawerClosingState )
		[self openViewsDrawer:sender];
	else if( [viewsDrawer state] == NSDrawerOpenState || [viewsDrawer state] == NSDrawerOpeningState )
		[self closeViewsDrawer:sender];
}

- (IBAction) openViewsDrawer:(id) sender {
	int side = [[NSUserDefaults standardUserDefaults] integerForKey:@"JVChatWindowDrawerSide"];
	if( side == -1 ) [viewsDrawer openOnEdge:NSMinXEdge];
	else if( side == 1 ) [viewsDrawer openOnEdge:NSMaxXEdge];
	else [viewsDrawer open];

	[self setPreference:[NSNumber numberWithBool:YES] forKey:@"drawer open"];
}

- (IBAction) closeViewsDrawer:(id) sender {
	[viewsDrawer close];
	[self setPreference:[NSNumber numberWithBool:NO] forKey:@"drawer open"];
}

- (IBAction) toggleSmallDrawerIcons:(id) sender {
	_usesSmallIcons = ! _usesSmallIcons;
	[self setPreference:[NSNumber numberWithBool:_usesSmallIcons] forKey:@"small drawer icons"];
	[self _refreshList];
}

#pragma mark -

- (void) reloadListItem:(id <JVChatListItem>) item andChildren:(BOOL) children {
	id selectItem = [self selectedListItem];

	[chatViewsOutlineView reloadItem:item reloadChildren:( children && [chatViewsOutlineView isItemExpanded:item] ? YES : NO )];

	if( _activeViewController == item )
		[self _refreshWindowTitle];

	if( [self isMemberOfClass:[JVChatWindowController class]] && [[NSUserDefaults standardUserDefaults] boolForKey:@"JVKeepActiveDrawerPanelsVisible"] && [item isKindOfClass:[JVDirectChatPanel class]] && [(id)item newMessagesWaiting] ) {
		NSRange visibleRows = [chatViewsOutlineView rowsInRect:[chatViewsOutlineView visibleRect]];
		int row = [chatViewsOutlineView rowForItem:item];

		if( ! NSLocationInRange( row, visibleRows ) && row > 0 ) {
			int index = [_views indexOfObjectIdenticalTo:item];

			row = ( index > row ? NSMaxRange( visibleRows ) : visibleRows.location + 1 );
			id <JVChatListItem> rowItem = [chatViewsOutlineView itemAtRow:row];

			// this will break if the list has more than 2 levels
			if( [chatViewsOutlineView levelForRow:row] > 0 )
				rowItem = [rowItem parent];
			if( rowItem ) row = [_views indexOfObjectIdenticalTo:rowItem];

			if( rowItem && row != NSNotFound ) {
				[item retain];
				[_views removeObjectAtIndex:index];
				[_views insertObject:item atIndex:( index > row || ! row ? row : row - 1 )];
				[item release];
				[chatViewsOutlineView reloadData];
			}
		}
	}

	if( item == selectItem )
		[self _refreshSelectionMenu];

	if( selectItem ) {
		int selectedRow = [chatViewsOutlineView rowForItem:selectItem];
		[chatViewsOutlineView selectRow:selectedRow byExtendingSelection:NO];
	}
}

- (BOOL) isListItemExpanded:(id <JVChatListItem>) item {
	return [chatViewsOutlineView isItemExpanded:item];
}

- (void) expandListItem:(id <JVChatListItem>) item {
	[chatViewsOutlineView expandItem:item];
}

- (void) collapseListItem:(id <JVChatListItem>) item {
	[chatViewsOutlineView collapseItem:item];
}

#pragma mark -

- (BOOL) validateMenuItem:(NSMenuItem *) menuItem {
	if( [menuItem action] == @selector( toggleSmallDrawerIcons: ) ) {
		[menuItem setState:( _usesSmallIcons ? NSOnState : NSOffState )];
		return YES;
	} else if( [menuItem action] == @selector( toggleViewsDrawer: ) ) {
		if( [viewsDrawer state] == NSDrawerClosedState || [viewsDrawer state] == NSDrawerClosingState ) {
			[menuItem setTitle:[NSString stringWithFormat:NSLocalizedString( @"Show Drawer", "show drawer menu title" )]];
		} else {
			[menuItem setTitle:[NSString stringWithFormat:NSLocalizedString( @"Hide Drawer", "hide drawer menu title" )]];
		}
		return YES;
	} else if( [menuItem action] == @selector( getInfo: ) ) {
		id item = [self selectedListItem];
		if( [item conformsToProtocol:@protocol( JVInspection )] ) return YES;
		else return NO;
	} else if( [menuItem action] == @selector( closeCurrentPanel: ) ) {
		if( [[menuItem keyEquivalent] length] ) return YES;
		else return NO;
	} else if( [menuItem action] == @selector( detachCurrentPanel: ) ) {
		if( [_views count] > 1 ) return YES;
		else return NO;
	}

	if( [[self activeChatViewController] respondsToSelector:@selector( validateMenuItem: )] )
		return [(id)[self activeChatViewController] validateMenuItem:menuItem];
	
	return YES;
}
@end

#pragma mark -

@implementation JVChatWindowController (JVChatWindowControllerDelegate)
- (NSSize) drawerWillResizeContents:(NSDrawer *) drawer toSize:(NSSize) contentSize {
	[self setPreference:NSStringFromSize( contentSize ) forKey:@"drawer size"];
	return contentSize;
}

#pragma mark -

- (void) windowWillClose:(NSNotification *) notification {
    if( ! [[[[[NSApplication sharedApplication] keyWindow] windowController] className] isEqual:[self className]] )
		[self _resignMenuCommands];
    if( [[self window] isVisible] )
		[self close];
}

- (BOOL) windowShouldClose:(id) sender {
	if( [[self chatViewControllersWithControllerClass:[JVChatRoomPanel class]] count] <= 1 ) return YES; // no rooms, close without a prompt
	if( NSRunCriticalAlertPanelRelativeToWindow( NSLocalizedString( @"Are you sure you want to part from all chat rooms and close this window?", "are you sure you want to part all chat rooms dialog title" ), NSLocalizedString( @"You will exit all chat rooms and lose any unsaved chat transcripts. Do you want to proceed?", "confirm close of window message" ), @"Close", @"Cancel", nil, [self window] ) == NSOKButton )
		return YES;
	return NO;
}

- (void) windowDidResignKey:(NSNotification *) notification {
    if( ! [[[[[NSApplication sharedApplication] keyWindow] windowController] className] isEqual:[self className]] )
		[self _resignMenuCommands];
}

- (void) windowDidBecomeKey:(NSNotification *) notification {
	[self _claimMenuCommands];
	if( _activeViewController ) {
		[[self window] makeFirstResponder:[_activeViewController firstResponder]];
		[self reloadListItem:_activeViewController andChildren:NO];
	}
}

- (void) windowDidMove:(NSNotification *) notification {
	[self _saveWindowFrame];
}

- (void) windowDidResize:(NSNotification *) notification {
	[self _saveWindowFrame];
}

#pragma mark -

- (void) outlineView:(NSOutlineView *) outlineView willDisplayCell:(id) cell forTableColumn:(NSTableColumn *) tableColumn item:(id) item {
	[(JVDetailCell *) cell setRepresentedObject:item];
	[(JVDetailCell *) cell setMainText:[item title]];

	if( [item respondsToSelector:@selector( information )] ) {
		[(JVDetailCell *) cell setInformationText:[item information]];
	} else [(JVDetailCell *) cell setInformationText:nil];

	if( [item respondsToSelector:@selector( statusImage )] ) {
		[(JVDetailCell *) cell setStatusImage:[item statusImage]];
	} else [(JVDetailCell *) cell setStatusImage:nil];

	if( [item respondsToSelector:@selector( isEnabled )] ) {
		[cell setEnabled:[item isEnabled]];
	} else [cell setEnabled:YES];

	if( [item respondsToSelector:@selector( newMessagesWaiting )] ) {
		[(JVDetailCell *) cell setStatusNumber:[item newMessagesWaiting]];
	} else [(JVDetailCell *) cell setStatusNumber:0];

	if( [item respondsToSelector:@selector( newHighlightMessagesWaiting )] ) {
		[(JVDetailCell *) cell setImportantStatusNumber:[item newHighlightMessagesWaiting]];
	} else [(JVDetailCell *) cell setImportantStatusNumber:0];
}

- (NSString *) outlineView:(NSOutlineView *) outlineView toolTipForCell:(NSCell *) cell rect:(NSRectPointer) rect tableColumn:(NSTableColumn *) tableColumn item:(id) item mouseLocation:(NSPoint) mouseLocation {
	if( [item respondsToSelector:@selector( toolTip )] )
		return [item toolTip];
	return nil;
}

- (NSString *) outlineView:(NSOutlineView *) outlineView toolTipForItem:(id) item inTrackingRect:(NSRect) rect forCell:(id) cell {
	if( [item respondsToSelector:@selector( toolTip )] )
		return [item toolTip];
	return nil;
}

- (int) outlineView:(NSOutlineView *) outlineView numberOfChildrenOfItem:(id) item {
	if( item && [item respondsToSelector:@selector( numberOfChildren )] ) return [item numberOfChildren];
	else return [_views count];
}

- (BOOL) outlineView:(NSOutlineView *) outlineView isItemExpandable:(id) item {
	return ( [item respondsToSelector:@selector( numberOfChildren )] && [item numberOfChildren] ? YES : NO );
}

- (id) outlineView:(NSOutlineView *) outlineView child:(int) index ofItem:(id) item {
	if( item ) {
		if( [item respondsToSelector:@selector( childAtIndex: )] )
			return [item childAtIndex:index];
		else return nil;
	} else return [_views objectAtIndex:index];
}

- (id) outlineView:(NSOutlineView *) outlineView objectValueForTableColumn:(NSTableColumn *) tableColumn byItem:(id) item {
	float maxSideSize = ( ( _usesSmallIcons || [outlineView levelForRow:[outlineView rowForItem:item]] ) ? 16. : 32. );
	NSImage *org = [item icon];

	if( [org size].width > maxSideSize || [org size].height > maxSideSize ) {
		NSImage *ret = [[[item icon] copyWithZone:nil] autorelease];
		[ret setScalesWhenResized:YES];
		[ret setSize:NSMakeSize( maxSideSize, maxSideSize )];
		org = ret;
	}

	return org;
}

- (BOOL) outlineView:(NSOutlineView *) outlineView shouldEditTableColumn:(NSTableColumn *) tableColumn item:(id) item {
	return NO;
}

- (BOOL) outlineView:(NSOutlineView *) outlineView shouldExpandItem:(id) item {
	if( [[[NSApplication sharedApplication] currentEvent] type] == NSLeftMouseDragged ) return NO; // if we are dragging don't expand
	return YES;
}

- (BOOL) outlineView:(NSOutlineView *) outlineView shouldCollapseItem:(id) item {
	if( [self selectedListItem] != [self activeChatViewController] )
		[outlineView selectRow:[outlineView rowForItem:[self activeChatViewController]] byExtendingSelection:NO];
	return YES;
}

- (int) outlineView:(NSOutlineView *) outlineView heightOfRow:(int) row {
	return ( [outlineView levelForRow:row] || _usesSmallIcons ? 16 : 34 );
}

- (void) outlineViewSelectionDidChange:(NSNotification *) notification {
	id item = [self selectedListItem];

	[[JVInspectorController sharedInspector] inspectObject:[self objectToInspect]];

	if( [item conformsToProtocol:@protocol( JVChatViewController )] && item != (id) _activeViewController )
		[self _refreshWindow];

	[self _refreshSelectionMenu];
}

- (BOOL) outlineView:(NSOutlineView *) outlineView writeItems:(NSArray *) items toPasteboard:(NSPasteboard *) board {
	id item = [items lastObject];
	NSData *data = [NSData dataWithBytes:&item length:sizeof( &item )];
	if( ! [item conformsToProtocol:@protocol( JVChatViewController )] ) return NO;
	[board declareTypes:[NSArray arrayWithObjects:JVChatViewPboardType, nil] owner:self];
	[board setData:data forType:JVChatViewPboardType];
	return YES;
}

- (NSDragOperation) outlineView:(NSOutlineView *) outlineView validateDrop:(id <NSDraggingInfo>) info proposedItem:(id) item proposedChildIndex:(int) index {
	if( [[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:NSFilenamesPboardType]] ) {
		if( [item respondsToSelector:@selector( acceptsDraggedFileOfType: )] ) {
			NSArray *files = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
			NSEnumerator *enumerator = [files objectEnumerator];
			id file = nil;

			while( ( file = [enumerator nextObject] ) )
				if( [item acceptsDraggedFileOfType:[file pathExtension]] )
					return NSDragOperationMove;

			return NSDragOperationNone;
		} else return NSDragOperationNone;
	} else if( [[info draggingPasteboard] availableTypeFromArray:[NSArray arrayWithObject:JVChatViewPboardType]] ) {
		if( ! item ) return NSDragOperationMove;
		else return NSDragOperationNone;
	} else return NSDragOperationNone;
}

- (BOOL) outlineView:(NSOutlineView *) outlineView acceptDrop:(id <NSDraggingInfo>) info item:(id) item childIndex:(int) index {
	NSPasteboard *board = [info draggingPasteboard];
	if( [board availableTypeFromArray:[NSArray arrayWithObject:NSFilenamesPboardType]] ) {
		NSArray *files = [[info draggingPasteboard] propertyListForType:NSFilenamesPboardType];
		NSEnumerator *enumerator = [files objectEnumerator];
		id file = nil;

		if( ! [item respondsToSelector:@selector( acceptsDraggedFileOfType: )] || ! [item respondsToSelector:@selector( handleDraggedFile: )] ) return NO;

		while( ( file = [enumerator nextObject] ) )
			if( [item acceptsDraggedFileOfType:[file pathExtension]] )
				[item handleDraggedFile:file];

		return YES;
	} else if( [board availableTypeFromArray:[NSArray arrayWithObject:JVChatViewPboardType]] ) {
		NSData *pointerData = [board dataForType:JVChatViewPboardType];
		id <JVChatViewController> dragedController = nil;
		[pointerData getBytes:&dragedController];
		[dragedController retain];

		if( [_views containsObject:dragedController] ) {
			if( index != NSOutlineViewDropOnItemIndex && index >= (int) [_views indexOfObjectIdenticalTo:dragedController] ) index--;
			[_views removeObjectIdenticalTo:dragedController];
		} else {
			[[dragedController windowController] removeChatViewController:dragedController];
		}

		if( index == NSOutlineViewDropOnItemIndex ) [self addChatViewController:dragedController];
		else [self insertChatViewController:dragedController atIndex:index];

		[dragedController release];
		return YES;
	}

	return NO;
}

- (void) outlineViewItemDidCollapse:(NSNotification *) notification {
	[chatViewsOutlineView performSelector:@selector( sizeLastColumnToFit ) withObject:nil afterDelay:0.];
	[chatViewsOutlineView performSelector:@selector( display ) withObject:nil afterDelay:0.];
	id item = [[notification userInfo] objectForKey:@"NSObject"];
	if( [item respondsToSelector:@selector( setPreference:forKey: )] )
		[(id)item setPreference:[NSNumber numberWithBool:NO] forKey:@"expanded"];
}

- (void) outlineViewItemDidExpand:(NSNotification *) notification {
	[chatViewsOutlineView performSelector:@selector( sizeLastColumnToFit ) withObject:nil afterDelay:0.];
	id item = [[notification userInfo] objectForKey:@"NSObject"];
	if( [item respondsToSelector:@selector( setPreference:forKey: )] )
		[(id)item setPreference:[NSNumber numberWithBool:YES] forKey:@"expanded"];
}
@end

#pragma mark -

@implementation JVChatWindowController (JVChatWindowControllerPrivate)
- (void) _claimMenuCommands {
	NSMenuItem *closeItem = [[[[[NSApplication sharedApplication] mainMenu] itemAtIndex:1] submenu] itemWithTag:1];
	[closeItem setKeyEquivalentModifierMask:NSCommandKeyMask];
	[closeItem setKeyEquivalent:@"W"];

	closeItem = (NSMenuItem *)[[[[[NSApplication sharedApplication] mainMenu] itemAtIndex:1] submenu] itemWithTag:2];
	[closeItem setKeyEquivalentModifierMask:NSCommandKeyMask];
	[closeItem setKeyEquivalent:@"w"];
}

- (void) _resignMenuCommands {
	NSMenuItem *closeItem = [[[[[NSApplication sharedApplication] mainMenu] itemAtIndex:1] submenu] itemWithTag:1];
	[closeItem setKeyEquivalentModifierMask:NSCommandKeyMask];
	[closeItem setKeyEquivalent:@"w"];

	closeItem = (NSMenuItem *)[[[[[NSApplication sharedApplication] mainMenu] itemAtIndex:1] submenu] itemWithTag:2];
	[closeItem setKeyEquivalentModifierMask:0];
	[closeItem setKeyEquivalent:@""];
}

- (IBAction) _doubleClickedListItem:(id) sender {
	id item = [self selectedListItem];
	if( [item respondsToSelector:@selector( doubleClicked: )] )
		[item doubleClicked:sender];
}

- (void) _refreshSelectionMenu {
	id item = [self selectedListItem];
	if( ! item ) item = [self activeChatViewController];

	id menuItem = nil;
	NSMenu *menu = [chatViewsOutlineView menu];
	NSMenu *newMenu = ( [item respondsToSelector:@selector( menu )] ? [item menu] : nil );

	NSEnumerator *enumerator = [[[[menu itemArray] copyWithZone:nil] autorelease] objectEnumerator];
	while( ( menuItem = [enumerator nextObject] ) )
		[menu removeItem:menuItem];

	enumerator = [[[[newMenu itemArray] copyWithZone:nil] autorelease] objectEnumerator];
	while( ( menuItem = [enumerator nextObject] ) ) {
		[newMenu removeItem:menuItem];
		[menu addItem:menuItem];
	}

	NSMethodSignature *signature = [NSMethodSignature methodSignatureWithReturnAndArgumentTypes:@encode( NSArray * ), @encode( id ), @encode( id ), nil];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
	id view = [item parent];
	if( ! view ) view = item;

	[invocation setSelector:@selector( contextualMenuItemsForObject:inView: )];
	[invocation setArgument:&item atIndex:2];
	[invocation setArgument:&view atIndex:3];

	NSArray *results = [[MVChatPluginManager defaultManager] makePluginsPerformInvocation:invocation];
	if( [results count] ) {
		[menu addItem:[NSMenuItem separatorItem]];

		NSArray *items = nil;
		enumerator = [results objectEnumerator];
		while( ( items = [enumerator nextObject] ) ) {
			if( ! [items respondsToSelector:@selector( objectEnumerator )] ) continue;
			NSEnumerator *ienumerator = [items objectEnumerator];
			while( ( menuItem = [ienumerator nextObject] ) )
				if( [menuItem isKindOfClass:[NSMenuItem class]] ) [menu addItem:menuItem];
		}

		if( [[[menu itemArray] lastObject] isSeparatorItem] )
			[menu removeItem:[[menu itemArray] lastObject]];
	}

	if( [menu numberOfItems] ) {
		[viewActionButton setEnabled:YES];
		[viewActionButton setMenu:menu];
	} else [viewActionButton setEnabled:NO];
}

- (void) _refreshWindow {
	[[self window] disableFlushWindow];

	id item = [self selectedListItem];
	if( ! item ) goto end;

	if( ( [item conformsToProtocol:@protocol( JVChatViewController )] && item != (id) _activeViewController ) || ( ! _activeViewController && [[item parent] conformsToProtocol:@protocol( JVChatViewController )] && ( item = [item parent] ) ) ) {
		id lastActive = _activeViewController;
		if( [_activeViewController respondsToSelector:@selector( willUnselect )] )
			[(NSObject *)_activeViewController willUnselect];
		if( [item respondsToSelector:@selector( willSelect )] )
			[(NSObject *)item willSelect];

		id old = _activeViewController;
		_activeViewController = [item retain];
		[old release];

		[[self window] setContentView:[_activeViewController view]];
		[[self window] setToolbar:[_activeViewController toolbar]];
		[[self window] makeFirstResponder:[[_activeViewController view] nextKeyView]];

		if( [lastActive respondsToSelector:@selector( didUnselect )] )
			[(NSObject *)lastActive didUnselect];
		if( [_activeViewController respondsToSelector:@selector( didSelect )] )
			[(NSObject *)_activeViewController didSelect];
	} else if( ! [_views count] || ! _activeViewController ) {
		NSView *placeHolder = [[NSView alloc] initWithFrame:[[[self window] contentView] frame]];
		[[self window] setContentView:placeHolder];
		[placeHolder release];

		[[[self window] toolbar] setDelegate:nil];
		[[self window] setToolbar:nil];
		[[self window] makeFirstResponder:nil];
	}

	[self _refreshWindowTitle];

end:
	[[self window] enableFlushWindow];
	[[self window] displayIfNeeded];
}

- (void) _refreshWindowTitle {
	NSString *title = [_activeViewController windowTitle];
	if( ! title ) title = @"";
	[[self window] setTitle:title];
}

- (void) _refreshList {
	id selectItem = [self selectedListItem];

	[chatViewsOutlineView reloadData];
	[chatViewsOutlineView sizeLastColumnToFit];

	if( selectItem ) {
		int selectedRow = [chatViewsOutlineView rowForItem:selectItem];
		[chatViewsOutlineView selectRow:selectedRow byExtendingSelection:NO];
	}
}

- (void) _refreshPreferences {
	NSSize drawerSize = NSSizeFromString( [self preferenceForKey:@"drawer size"] );
	if( drawerSize.width ) [viewsDrawer setContentSize:drawerSize];

	if( [[self preferenceForKey:@"drawer open"] boolValue] )
		[self performSelector:@selector( openViewsDrawer: ) withObject:nil afterDelay:0.0];

	_usesSmallIcons = [[self preferenceForKey:@"small drawer icons"] boolValue];	
}

- (void) _saveWindowFrame {
	if( [[self identifier] length] ) {
		[[self window] saveFrameUsingName:@"Chat Window"];
		[[self window] saveFrameUsingName:[NSString stringWithFormat:@"Chat Window %@", [self identifier]]];
	} else {
		NSEnumerator *enumerator = [[self allChatViewControllers] objectEnumerator];
		id <JVChatViewController> controller = nil;

		[[self window] saveFrameUsingName:@"Chat Window"];

		while( ( controller = [enumerator nextObject] ) )
			[[self window] saveFrameUsingName:[NSString stringWithFormat:@"Chat Window %@", [controller identifier]]];
	}
}

- (void) _switchViews:(id) sender {
	[self showChatViewController:[sender representedObject]];
}
@end

#pragma mark -

@implementation NSWindow (JVChatWindowControllerScripting)
- (id <JVChatViewController>) activeChatViewController {
	if( ! [[self windowController] isKindOfClass:[JVChatWindowController class]] ) return nil;
	return [[self windowController] activeChatViewController];
}

- (id <JVChatListItem>) selectedListItem {
	if( ! [[self windowController] isKindOfClass:[JVChatWindowController class]] ) return nil;
	return [[self windowController] selectedListItem];
}

#pragma mark -

- (NSArray *) chatViews {
	if( ! [[self windowController] isKindOfClass:[JVChatWindowController class]] ) return nil;
	return [(JVChatWindowController *)[self windowController] allChatViewControllers];
}

- (id <JVChatViewController>) valueInChatViewsAtIndex:(unsigned) index {
	return [[self chatViews] objectAtIndex:index];
}

- (id <JVChatViewController>) valueInChatViewsWithUniqueID:(id) identifier {
	NSEnumerator *enumerator = [[self chatViews] objectEnumerator];
	id <JVChatViewController, JVChatListItemScripting> view = nil;

	while( ( view = [enumerator nextObject] ) )
		if( [[view uniqueIdentifier] isEqual:identifier] )
			return view;

	return nil;
}

- (id <JVChatViewController>) valueInChatViewsWithName:(NSString *) name {
	NSEnumerator *enumerator = [[self chatViews] objectEnumerator];
	id <JVChatViewController> view = nil;

	while( ( view = [enumerator nextObject] ) )
		if( [[view title] isEqualToString:name] )
			return view;

	return nil;
}

- (void) addInChatViews:(id <JVChatViewController>) view {
	if( ! [[self windowController] isKindOfClass:[JVChatWindowController class]] ) return;
	[[self windowController] addChatViewController:view];
}

- (void) insertInChatViews:(id <JVChatViewController>) view {
	if( ! [[self windowController] isKindOfClass:[JVChatWindowController class]] ) return;
	[[self windowController] addChatViewController:view];
}

- (void) insertInChatViews:(id <JVChatViewController>) view atIndex:(int) index {
	if( ! [[self windowController] isKindOfClass:[JVChatWindowController class]] ) return;
	[[self windowController] insertChatViewController:view atIndex:index];
}

- (void) removeFromViewsAtIndex:(unsigned) index {
	if( ! [[self windowController] isKindOfClass:[JVChatWindowController class]] ) return;
	[[self windowController] removeChatViewControllerAtIndex:index];
}

- (void) replaceInChatViews:(id <JVChatViewController>) view atIndex:(unsigned) index {
	if( ! [[self windowController] isKindOfClass:[JVChatWindowController class]] ) return;
	[[self windowController] replaceChatViewControllerAtIndex:index withController:view];
}

#pragma mark -

- (NSArray *) chatViewsWithClass:(Class) class {
	NSMutableArray *ret = [NSMutableArray array];
	NSEnumerator *enumerator = [[self chatViews] objectEnumerator];
	id <JVChatViewController> item = nil;

	while( ( item = [enumerator nextObject] ) )
		if( [item isMemberOfClass:class] )
			[ret addObject:item];

	return ret;
}

- (id <JVChatViewController>) valueInChatViewsAtIndex:(unsigned) index withClass:(Class) class {
	return [[self chatViewsWithClass:class] objectAtIndex:index];
}

- (id <JVChatViewController>) valueInChatViewsWithUniqueID:(id) identifier andClass:(Class) class {
	return [self valueInChatViewsWithUniqueID:identifier];
}

- (id <JVChatViewController>) valueInChatViewsWithName:(NSString *) name andClass:(Class) class {
	NSEnumerator *enumerator = [[self chatViewsWithClass:class] objectEnumerator];
	id <JVChatViewController> view = nil;

	while( ( view = [enumerator nextObject] ) )
		if( [[view title] isEqualToString:name] )
			return view;

	return nil;
}

- (void) addInChatViews:(id <JVChatViewController>) view withClass:(Class) class {
	unsigned int index = [[self chatViews] indexOfObject:[[self chatViewsWithClass:class] lastObject]];
	[self insertInChatViews:view atIndex:( index + 1 )];
}

- (void) insertInChatViews:(id <JVChatViewController>) view atIndex:(unsigned) index withClass:(Class) class {
	if( index == [[self chatViewsWithClass:class] count] ) {
		[self addInChatViews:view withClass:class];
	} else {
		unsigned int indx = [[self chatViews] indexOfObject:[[self chatViewsWithClass:class] objectAtIndex:index]];
		[self insertInChatViews:view atIndex:indx];
	}
}

- (void) removeFromChatViewsAtIndex:(unsigned) index withClass:(Class) class {
	unsigned int indx = [[self chatViews] indexOfObject:[[self chatViewsWithClass:class] objectAtIndex:index]];
	[self removeFromViewsAtIndex:indx];
}

- (void) replaceInChatViews:(id <JVChatViewController>) view atIndex:(unsigned) index withClass:(Class) class {
	unsigned int indx = [[self chatViews] indexOfObject:[[self chatViewsWithClass:class] objectAtIndex:index]];
	[self replaceInChatViews:view atIndex:indx];
}

#pragma mark -

- (NSArray *) chatRooms {
	return [self chatViewsWithClass:[JVChatRoomPanel class]];
}

- (id <JVChatViewController>) valueInChatRoomsAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVChatRoomPanel class]];
}

- (id <JVChatViewController>) valueInChatRoomsWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVChatRoomPanel class]];
}

- (id <JVChatViewController>) valueInChatRoomsWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVChatRoomPanel class]];
}

- (void) addInChatRooms:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatRoomPanel class]];
}

- (void) insertInChatRooms:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatRoomPanel class]];
}

- (void) insertInChatRooms:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self insertInChatViews:view atIndex:index withClass:[JVChatRoomPanel class]];
}

- (void) removeFromChatRoomsAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVChatRoomPanel class]];
}

- (void) replaceInChatRooms:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self replaceInChatViews:view atIndex:index withClass:[JVChatRoomPanel class]];
}

#pragma mark -

- (NSArray *) directChats {
	return [self chatViewsWithClass:[JVDirectChatPanel class]];
}

- (id <JVChatViewController>) valueInDirectChatsAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVDirectChatPanel class]];
}

- (id <JVChatViewController>) valueInDirectChatsWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVDirectChatPanel class]];
}

- (id <JVChatViewController>) valueInDirectChatsWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVDirectChatPanel class]];
}

- (void) addInDirectChats:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVDirectChatPanel class]];
}

- (void) insertInDirectChats:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVDirectChatPanel class]];
}

- (void) insertInDirectChats:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self insertInChatViews:view atIndex:index withClass:[JVDirectChatPanel class]];
}

- (void) removeFromDirectChatsAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVDirectChatPanel class]];
}

- (void) replaceInDirectChats:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self replaceInChatViews:view atIndex:index withClass:[JVDirectChatPanel class]];
}

#pragma mark -

- (NSArray *) chatTranscripts {
	return [self chatViewsWithClass:[JVChatTranscriptPanel class]];
}

- (id <JVChatViewController>) valueInChatTranscriptsAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVChatTranscriptPanel class]];
}

- (id <JVChatViewController>) valueInChatTranscriptsWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVChatTranscriptPanel class]];
}

- (id <JVChatViewController>) valueInChatTranscriptsWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVChatTranscriptPanel class]];
}

- (void) addInChatTranscripts:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatTranscriptPanel class]];
}

- (void) insertInChatTranscripts:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatTranscriptPanel class]];
}

- (void) insertInChatTranscripts:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self insertInChatViews:view atIndex:index withClass:[JVChatTranscriptPanel class]];
}

- (void) removeFromChatTranscriptsAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVChatTranscriptPanel class]];
}

- (void) replaceInChatTranscripts:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self replaceInChatViews:view atIndex:index withClass:[JVChatTranscriptPanel class]];
}

#pragma mark -

- (NSArray *) smartTranscripts {
	return [self chatViewsWithClass:[JVSmartTranscriptPanel class]];
}

- (id <JVChatViewController>) valueInSmartTranscriptsAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVSmartTranscriptPanel class]];
}

- (id <JVChatViewController>) valueInSmartTranscriptsWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVSmartTranscriptPanel class]];
}

- (id <JVChatViewController>) valueInSmartTranscriptsWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVSmartTranscriptPanel class]];
}

- (void) addInSmartTranscripts:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVSmartTranscriptPanel class]];
}

- (void) insertInSmartTranscripts:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVSmartTranscriptPanel class]];
}

- (void) insertInSmartTranscripts:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self insertInChatViews:view atIndex:index withClass:[JVSmartTranscriptPanel class]];
}

- (void) removeFromSmartTranscriptsAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVSmartTranscriptPanel class]];
}

- (void) replaceInSmartTranscripts:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self replaceInChatViews:view atIndex:index withClass:[JVSmartTranscriptPanel class]];
}

#pragma mark -

- (NSArray *) chatConsoles {
	return [self chatViewsWithClass:[JVChatConsolePanel class]];
}

- (id <JVChatViewController>) valueInChatConsolesAtIndex:(unsigned) index {
	return [self valueInChatViewsAtIndex:index withClass:[JVChatConsolePanel class]];
}

- (id <JVChatViewController>) valueInChatConsolesWithUniqueID:(id) identifier {
	return [self valueInChatViewsWithUniqueID:identifier andClass:[JVChatConsolePanel class]];
}

- (id <JVChatViewController>) valueInChatConsolesWithName:(NSString *) name {
	return [self valueInChatViewsWithName:name andClass:[JVChatConsolePanel class]];
}

- (void) addInChatConsoles:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatConsolePanel class]];
}

- (void) insertInChatConsoles:(id <JVChatViewController>) view {
	[self addInChatViews:view withClass:[JVChatConsolePanel class]];
}

- (void) insertInChatConsoles:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self insertInChatViews:view atIndex:index withClass:[JVChatConsolePanel class]];
}

- (void) removeFromChatConsolesAtIndex:(unsigned) index {
	[self removeFromChatViewsAtIndex:index withClass:[JVChatConsolePanel class]];
}

- (void) replaceInChatConsoles:(id <JVChatViewController>) view atIndex:(unsigned) index {
	[self replaceInChatViews:view atIndex:index withClass:[JVChatConsolePanel class]];
}

#pragma mark -

- (NSArray *) indicesOfObjectsByEvaluatingRangeSpecifier:(NSRangeSpecifier *) specifier {
	NSString *key = [specifier key];

	if( [key isEqualToString:@"chatViews"] || [key isEqualToString:@"chatRooms"] || [key isEqualToString:@"directChats"] || [key isEqualToString:@"chatConsoles"] || [key isEqualToString:@"chatTranscripts"] ) {
		NSScriptObjectSpecifier *startSpec = [specifier startSpecifier];
		NSScriptObjectSpecifier *endSpec = [specifier endSpecifier];
		NSString *startKey = [startSpec key];
		NSString *endKey = [endSpec key];
		NSArray *chatViews = [self chatViews];

		if( ! startSpec && ! endSpec ) return nil;

		if( ! [chatViews count] ) [NSArray array];

		if( ( ! startSpec || [startKey isEqualToString:@"chatViews"] || [startKey isEqualToString:@"chatRooms"] || [startKey isEqualToString:@"directChats"] || [startKey isEqualToString:@"chatConsoles"] || [startKey isEqualToString:@"chatTranscripts"] ) && ( ! endSpec || [endKey isEqualToString:@"chatViews"] || [endKey isEqualToString:@"chatRooms"] || [endKey isEqualToString:@"directChats"] || [endKey isEqualToString:@"chatConsoles"] || [endKey isEqualToString:@"chatTranscripts"] ) ) {
			unsigned startIndex = 0;
			unsigned endIndex = 0;

			// The strategy here is going to be to find the index of the start and stop object in the full graphics array, regardless of what its key is.  Then we can find what we're looking for in that range of the graphics key (weeding out objects we don't want, if necessary).
			// First find the index of the first start object in the graphics array
			if( startSpec ) {
				id startObject = [startSpec objectsByEvaluatingSpecifier];
				if( [startObject isKindOfClass:[NSArray class]] ) {
					if( ! [(NSArray *)startObject count] ) startObject = nil;
					else startObject = [startObject objectAtIndex:0];
				}
				if( ! startObject ) return nil;
				startIndex = [chatViews indexOfObjectIdenticalTo:startObject];
				if( startIndex == NSNotFound ) return nil;
			}

			// Now find the index of the last end object in the graphics array
			if( endSpec ) {
				id endObject = [endSpec objectsByEvaluatingSpecifier];
				if( [endObject isKindOfClass:[NSArray class]] ) {
					if( ! [(NSArray *)endObject count] ) endObject = nil;
					else endObject = [endObject lastObject];
				}
				if( ! endObject ) return nil;
				endIndex = [chatViews indexOfObjectIdenticalTo:endObject];
				if( endIndex == NSNotFound ) return nil;
			} else endIndex = ( [chatViews count] - 1 );

			// Accept backwards ranges gracefully
			if( endIndex < startIndex ) {
				unsigned temp = endIndex;
				endIndex = startIndex;
				startIndex = temp;
			}

			// Now startIndex and endIndex specify the end points of the range we want within the main array.
			// We will traverse the range and pick the objects we want.
			// We do this by getting each object and seeing if it actually appears in the real key that we are trying to evaluate in.
			NSMutableArray *result = [NSMutableArray array];
			BOOL keyIsGeneric = [key isEqualToString:@"chatViews"];
			NSArray *rangeKeyObjects = ( keyIsGeneric ? nil : [self valueForKey:key] );
			unsigned curKeyIndex = 0;
			id obj = nil;

			for( unsigned i = startIndex; i <= endIndex; i++ ) {
				if( keyIsGeneric ) {
					[result addObject:[NSNumber numberWithInt:i]];
				} else {
					obj = [chatViews objectAtIndex:i];
					curKeyIndex = [rangeKeyObjects indexOfObjectIdenticalTo:obj];
					if( curKeyIndex != NSNotFound )
						[result addObject:[NSNumber numberWithInt:curKeyIndex]];
				}
			}

			return result;
		}
	}

	return nil;
}

- (NSArray *) indicesOfObjectsByEvaluatingRelativeSpecifier:(NSRelativeSpecifier *) specifier {
	NSString *key = [specifier key];

	if( [key isEqualToString:@"chatViews"] || [key isEqualToString:@"chatRooms"] || [key isEqualToString:@"directChats"] || [key isEqualToString:@"chatConsoles"] || [key isEqualToString:@"chatTranscripts"] ) {
		NSScriptObjectSpecifier *baseSpec = [specifier baseSpecifier];
		NSString *baseKey = [baseSpec key];
		NSArray *chatViews = [self chatViews];
		NSRelativePosition relPos = [specifier relativePosition];

		if( ! baseSpec ) return nil;

		if( ! [chatViews count] ) return [NSArray array];

		if( [baseKey isEqualToString:@"chatViews"] || [baseKey isEqualToString:@"chatRooms"] || [baseKey isEqualToString:@"directChats"] || [baseKey isEqualToString:@"chatConsoles"] || [baseKey isEqualToString:@"chatTranscripts"] ) {
			unsigned baseIndex = 0;

			// The strategy here is going to be to find the index of the base object in the full graphics array, regardless of what its key is.  Then we can find what we're looking for before or after it.
			// First find the index of the first or last base object in the master array
			// Base specifiers are to be evaluated within the same container as the relative specifier they are the base of. That's this container.

			id baseObject = [baseSpec objectsByEvaluatingWithContainers:self];
			if( [baseObject isKindOfClass:[NSArray class]] ) {
				unsigned baseCount = [(NSArray *)baseObject count];
				if( baseCount ) {
					if( relPos == NSRelativeBefore ) baseObject = [baseObject objectAtIndex:0];
					else baseObject = [baseObject objectAtIndex:( baseCount - 1 )];
				} else baseObject = nil;
			}

			if( ! baseObject ) return nil;

			baseIndex = [chatViews indexOfObjectIdenticalTo:baseObject];
			if( baseIndex == NSNotFound ) return nil;

			// Now baseIndex specifies the base object for the relative spec in the master array.
			// We will start either right before or right after and look for an object that matches the type we want.
			// We do this by getting each object and seeing if it actually appears in the real key that we are trying to evaluate in.
			NSMutableArray *result = [NSMutableArray array];
			BOOL keyIsGeneric = [key isEqualToString:@"chatViews"];
			NSArray *relKeyObjects = ( keyIsGeneric ? nil : [self valueForKey:key] );
			unsigned curKeyIndex = 0, viewCount = [chatViews count];
			id obj = nil;

			if( relPos == NSRelativeBefore ) baseIndex--;
			else baseIndex++;

			while( baseIndex < viewCount ) {
				if( keyIsGeneric ) {
					[result addObject:[NSNumber numberWithInt:baseIndex]];
					break;
				} else {
					obj = [chatViews objectAtIndex:baseIndex];
					curKeyIndex = [relKeyObjects indexOfObjectIdenticalTo:obj];
					if( curKeyIndex != NSNotFound ) {
						[result addObject:[NSNumber numberWithInt:curKeyIndex]];
						break;
					}
				}

				if( relPos == NSRelativeBefore ) baseIndex--;
				else baseIndex++;
			}

			return result;
		}
	}

	return nil;
}

- (NSArray *) indicesOfObjectsByEvaluatingObjectSpecifier:(NSScriptObjectSpecifier *) specifier {
	if( [specifier isKindOfClass:[NSRangeSpecifier class]] ) {
		return [self indicesOfObjectsByEvaluatingRangeSpecifier:(NSRangeSpecifier *) specifier];
	} else if( [specifier isKindOfClass:[NSRelativeSpecifier class]] ) {
		return [self indicesOfObjectsByEvaluatingRelativeSpecifier:(NSRelativeSpecifier *) specifier];
	}
	return nil;
}
@end
