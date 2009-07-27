//
//  Catcher.m
//  PasteBoardCatcher
//
//  Created by Erica Sadun on 7/17/09.
//  Copyright 2009 Up To No Good, Inc.. All rights reserved.
//

#import "Catcher.h"
#import <AppKit/AppKit.h>
#import "TCPService.h"
#import "TCPConnection.h"

#define STRINGEQ(X,Y) ([X caseInsensitiveCompare:Y] == NSOrderedSame)
#define ANNOUNCE(format, ...) [self.statusText setTitleWithMnemonic:[NSString stringWithFormat:format, ##__VA_ARGS__]];

@implementation Catcher
@synthesize imageView;
@synthesize textField;
@synthesize statusText;
@synthesize button;
@synthesize progress;
@synthesize saveItem;
@synthesize imageData;
@synthesize browser;
@synthesize service;

// Build a properly oriented NSImage from the data
- (NSImage *) imageFromData: (NSData *) data
{
	NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
	
	// Recover orientation
	CGImageSourceRef imageSource = CGImageSourceCreateWithData ((CFDataRef)data, NULL);
	CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
    int orientation = [(NSNumber *)CFDictionaryGetValue(properties, kCGImagePropertyOrientation) intValue];
	CFRelease(properties);
    
	// Gather width and  height info
	CGImageRef imageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
    float x = 1; 
    float y = 1; 
    float w = CGImageGetWidth(imageRef);
    float h = CGImageGetHeight(imageRef);
	CFRelease(imageRef);
	CFRelease(imageSource);
    
	// Recover new size and new transform
    NSAffineTransformStruct ntms[8] = {
        { x, 0, 0, y, 0, 0}, {-x, 0, 0, y, w, 0},
        {-x, 0, 0,-y, w, h}, { x, 0, 0,-y, 0, h},
        { 0,-x,-y, 0, h, w}, { 0,-x, y, 0, 0, w}, 
		{ 0, x, y, 0, 0, 0}, { 0, x,-y, 0, h, 0} 
    };
	CGSize size = (orientation < 4)  ? CGSizeMake(w, h) : CGSizeMake(h, w);
	NSAffineTransformStruct nats = ntms[orientation - 1];

	// Build a (potentially) rotated image
	NSImage *rotated = [[NSImage alloc] initWithSize:NSSizeFromCGSize(size)];
	[rotated lockFocus];
	NSAffineTransform *transform = [NSAffineTransform transform];
	[transform setTransformStruct:nats];
	[transform concat];
	[image drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];
	[rotated unlockFocus];
	
	// Return the correctly oriented image
	return [rotated autorelease];
}

// Receive the image and update the interface
- (void) connection:(TCPConnection*)connection didReceiveData:(NSData*)data;
{
	success = YES;
	self.imageData = data;
	NSImage *image = [self imageFromData:data];
	[self.imageView setImage:image];
	
	[self.saveItem setEnabled:YES];
	[self.button setEnabled:YES];
	[self.service stop];
	self.service = nil;
	[self.progress stopAnimation:nil];
	
	ANNOUNCE(@"Recived JPEG image (%d bytes).\n\nUse File > Save to save the received image to disk.", data.length);
}

// If there was no success, apologize and restore UI
- (void) connectionDidClose:(TCPConnection*)connection
{
	if (success) return;
	ANNOUNCE(@"Connection denied or lost. Sorry.");
	
	if (self.service)
	{
		[self.service stop];
		self.service = nil;
	}

	self.imageData = nil;
	[self.saveItem setEnabled:NO];
	[self.imageView setImage:nil];
	[self.button setEnabled:YES];
	[self.progress stopAnimation:nil];
}

// Upon resolving address, create a connection to that address and request data
- (void)netServiceDidResolveAddress:(NSNetService *)netService
{
	NSArray* addresses = [netService addresses];
	if (addresses && [addresses count]) {
		struct sockaddr* address = (struct sockaddr*)[[addresses objectAtIndex:0] bytes];
		TCPConnection *connection = [[TCPConnection alloc] initWithRemoteAddress:address];
		[connection setDelegate:self];
		[self.statusText setTitleWithMnemonic:@"Requesting data..."];
		[self.progress startAnimation:nil];
		[connection receiveData];
	}
}

// Complain when resolve fails
- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
	[self.statusText setTitleWithMnemonic:@"Error resolving service. Sorry."];
}

// Upon finding a service, stop the browser and resolve
- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing
{
	[self.browser stop];
	self.browser = nil;
	[self.statusText setTitleWithMnemonic:@"Resolving service."];
	self.service = netService;
	[self.service setDelegate:self];
	[self.service resolveWithTimeout:0.0f];
}

// Begin a catch request, start the service browser, and update UI
- (IBAction) catchPlease: (id) sender
{
	success = NO;
	[self.statusText setTitleWithMnemonic:@"Scanning for service"];
	
	self.browser = [[[NSNetServiceBrowser alloc] init] autorelease];
	[self.browser setDelegate:self];
	NSString *type = [TCPConnection bonjourTypeFromIdentifier:@"PictureThrow"];
	[self.browser searchForServicesOfType:type inDomain:@"local"];
	
	[self.button setEnabled:NO];
	self.imageData = nil;
	[self.saveItem setEnabled:NO];
	[self.imageView setImage:nil];
}

// Write data to disk based on save panel settings
- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
{
	if (returnCode == NSCancelButton)
	{
		return;
	}
	else
	{
		[self.imageData writeToFile:[sheet filename] atomically:YES];
		[self.saveItem setEnabled:NO];
	}
}

// Launch a save panel to store data to disk
- (IBAction) savePlease: (id) sender
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	savePanel.delegate = self;
	
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
	formatter.dateFormat = @"hhmmss";
	NSString *fname = [NSString stringWithFormat:@"PictureCatch-%@.jpg", [formatter stringFromDate:[NSDate date]]];
	[savePanel beginSheetForDirectory:[NSHomeDirectory() stringByAppendingString:@"/Desktop"] file:fname modalForWindow:[[NSApplication sharedApplication] mainWindow] modalDelegate:self didEndSelector:@selector(savePanelDidEnd:returnCode:contextInfo:) contextInfo:nil];
}
@end
