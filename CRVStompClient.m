//
//  CRVStompClient.h
//  Objc-Stomp
//
//
//  Implements the Stomp Protocol v1.0
//  See: http://stomp.codehaus.org/Protocol
// 
//  Requires the AsyncSocket library
//  See: https://github.com/robbiehanson/CocoaAsyncSocket
//
//  See: LICENSE
//	Stefan Saasen <stefan@coravy.com>
//  Based on StompService.{h,m} by Scott Raymond <sco@scottraymond.net>.
#import "CRVStompClient.h"
#import "GCDAsyncSocket.h"

#define kStompDefaultPort			61613
#define kDefaultTimeout				15	//


// ============= http://stomp.codehaus.org/Protocol =============
#define kCommandConnect				@"CONNECT"
#define kCommandSend				@"SEND"
#define kCommandSubscribe			@"SUBSCRIBE"
#define kCommandUnsubscribe			@"UNSUBSCRIBE"
#define kCommandBegin				@"BEGIN"
#define kCommandCommit				@"COMMIT"
#define kCommandAbort				@"ABORT"
#define kCommandAck					@"ACK"
#define kCommandDisconnect			@"DISCONNECT"
#define	kControlChar				[NSString stringWithFormat:@"\n%C", 0] // TODO -> static

#define kAckClient					@"client"
#define kAckAuto					@"auto"

#define kResponseHeaderSession		@"session"
#define kResponseHeaderReceiptId	@"receipt-id"
#define kResponseHeaderErrorMessage @"message"

#define kResponseFrameConnected		@"CONNECTED"
#define kResponseFrameMessage		@"MESSAGE"
#define kResponseFrameReceipt		@"RECEIPT"
#define kResponseFrameError			@"ERROR"
// ============= http://stomp.codehaus.org/Protocol =============

#define CRV_RELEASE_SAFELY(__POINTER) { [__POINTER release]; __POINTER = nil; }

@interface CRVStompClient()
@property (nonatomic, assign) NSUInteger port;
@property (nonatomic, retain) GCDAsyncSocket *socket;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, copy) NSString *login;
@property (nonatomic, copy) NSString *passcode;
@property (nonatomic, copy) NSString *sessionId;
@end

@interface CRVStompClient(PrivateMethods)
- (void) sendFrame:(NSString *) command withHeader:(NSDictionary *) header andBody:(NSString *) body;
- (void) sendFrame:(NSString *) command;
- (void) readFrame;
@end

@implementation CRVStompClient

@synthesize delegate;
@synthesize connected;
@synthesize socket, host, port, login, passcode, sessionId;

- (id)init {
	return [self initWithHost:@"localhost" port:kStompDefaultPort login:nil passcode:nil delegate:nil];
}

- (id)initWithHost:(NSString *)theHost 
			  port:(NSUInteger)thePort 
		  delegate:(id<CRVStompClientDelegate>)theDelegate
	   autoconnect:(BOOL) autoconnect {
	if((self = [self initWithHost:theHost port:thePort login:nil passcode:nil delegate:theDelegate autoconnect: autoconnect])) {
		anonymous = YES;
	}
	return self;
}

- (id)initWithHost:(NSString *)theHost 
			  port:(NSUInteger)thePort 
			 login:(NSString *)theLogin 
		  passcode:(NSString *)thePasscode 
		  delegate:(id<CRVStompClientDelegate>)theDelegate {
	return [self initWithHost:theHost port:thePort login:theLogin passcode:thePasscode delegate:theDelegate autoconnect: NO];
}

- (void)connectToHost {
    NSError *err;
    if(![socket connectToHost:self.host onPort:self.port error:&err]) {
        NSLog(@"StompService error: %@", err);
    }
}

- (id)initWithHost:(NSString *)theHost 
			  port:(NSUInteger)thePort 
			 login:(NSString *)theLogin 
		  passcode:(NSString *)thePasscode 
		  delegate:(id<CRVStompClientDelegate>)theDelegate
	   autoconnect:(BOOL) autoconnect {
	if((self = [super init])) {
		anonymous = NO;
		doAutoconnect = autoconnect;
		
		GCDAsyncSocket *theSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
		[self setSocket: theSocket];
		[theSocket release];
		
		[self setDelegate:theDelegate];
		[self setHost: theHost];
		[self setPort: thePort];
		[self setLogin: theLogin];
		[self setPasscode: thePasscode];
	}
	return self;
}

#pragma mark -
#pragma mark Public methods


- (void)loginToServer {
	if (anonymous) {
		[self sendFrame:kCommandConnect];
	} else {
		NSDictionary *headers = [NSDictionary dictionaryWithObjectsAndKeys: [self login], @"login", [self passcode], @"passcode", nil];
		[self sendFrame:kCommandConnect withHeader:headers andBody: nil];
	}
	[self readFrame];
}


- (void)disconnect {
	[self sendFrame:kCommandDisconnect];
	[[self socket] disconnectAfterReadingAndWriting];
}


- (void)sendMessage:(NSString *)theMessage toDestination:(NSString *)destination {
	NSDictionary *headers = [NSDictionary dictionaryWithObjectsAndKeys: destination, @"destination", nil];
    [self sendFrame:kCommandSend withHeader:headers andBody:theMessage];
}

- (void)subscribeToDestination:(NSString *)destination {
    if (!connected) {
        NSLog(@"CRVStompClient: ERROR: Cannot subscribe to destination because we are not conncted");
        return;
    }
	[self subscribeToDestination:destination withAck: CRVStompAckModeAuto];
}

- (void)subscribeToDestination:(NSString *)destination withAck:(CRVStompAckMode) ackMode {
	NSString *ack;
	switch (ackMode) {
		case CRVStompAckModeClient:
			ack = kAckClient;
			break;
		default:
			ack = kAckAuto;
			break;
	}
	NSDictionary *headers = [NSDictionary dictionaryWithObjectsAndKeys: destination, @"destination", ack, @"ack", nil];
    [self sendFrame:kCommandSubscribe withHeader:headers andBody:nil];
}

- (void)subscribeToDestination:(NSString *)destination withHeader:(NSDictionary *) header {
	NSMutableDictionary *headers = [[NSMutableDictionary alloc] initWithDictionary:header];
	[headers setObject:destination forKey:@"destination"];
    [self sendFrame:kCommandSubscribe withHeader:headers andBody:nil];
	[headers release];
}

- (void)unsubscribeFromDestination:(NSString *)destination {
	NSDictionary *headers = [NSDictionary dictionaryWithObjectsAndKeys: destination, @"destination", nil];
    [self sendFrame:kCommandUnsubscribe withHeader:headers andBody:nil];
}

-(void)begin:(NSString *)transactionId {
	NSDictionary *headers = [NSDictionary dictionaryWithObjectsAndKeys: transactionId, @"transaction", nil];
    [self sendFrame:kCommandBegin withHeader:headers andBody:nil];
}

- (void)commit:(NSString *)transactionId {
	NSDictionary *headers = [NSDictionary dictionaryWithObjectsAndKeys: transactionId, @"transaction", nil];
    [self sendFrame:kCommandCommit withHeader:headers andBody:nil];
}

- (void)abort:(NSString *)transactionId {
	NSDictionary *headers = [NSDictionary dictionaryWithObjectsAndKeys: transactionId, @"transaction", nil];
    [self sendFrame:kCommandAbort withHeader:headers andBody:nil];
}

- (void)ack:(NSString *)messageId {
	NSDictionary *headers = [NSDictionary dictionaryWithObjectsAndKeys: messageId, @"message-id", nil];
    [self sendFrame:kCommandAck withHeader:headers andBody:nil];
}



#pragma mark -
#pragma mark PrivateMethods
- (void) sendFrame:(NSString *) command withHeader:(NSDictionary *) header andBody:(NSString *) body {
    NSMutableString *frameString = [NSMutableString stringWithString: [command stringByAppendingString:@"\n"]];	
	for (id key in header) {
		[frameString appendString:key];
		[frameString appendString:@":"];
		[frameString appendString:[header objectForKey:key]];
		[frameString appendString:@"\n"];
	}
	if (body) {
		[frameString appendString:@"\n"];
		[frameString appendString:body];
	}
    [frameString appendString:kControlChar];
	[[self socket] writeData:[frameString dataUsingEncoding:NSASCIIStringEncoding] withTimeout:kDefaultTimeout tag:123];
}

- (void) sendFrame:(NSString *) command {
	[self sendFrame:command withHeader:nil andBody:nil];
}

- (void)receiveFrame:(NSString *)command headers:(NSDictionary *)headers body:(NSString *)body {
    
#ifdef GLOBAL_DEBUG_LEVEL
    if(GLOBAL_DEBUG_LEVEL >= 10) NSLog(@"[CRVStompClient] CRVStompClient: receiveCommand '%@' [%@], %@", command, headers, body);
#endif
	
	// Connected
	if([kResponseFrameConnected isEqual:command]) {
        connected = TRUE;
		if([[self delegate] respondsToSelector:@selector(stompClientDidConnect:)]) {
			[[self delegate] stompClientDidConnect:self];
		}
		
		// store session-id
		NSString *sessId = [headers valueForKey:kResponseHeaderSession];
		[self setSessionId: sessId];
	
	// Response 
	} else if([kResponseFrameMessage isEqual:command]) {
		[[self delegate] stompClient:self messageReceived:body withHeader:headers];
		
	// Receipt
	} else if([kResponseFrameReceipt isEqual:command]) {		
		if([[self delegate] respondsToSelector:@selector(serverDidSendReceipt:withReceiptId:)]) {
			NSString *receiptId = [headers valueForKey:kResponseHeaderReceiptId];
			[[self delegate] serverDidSendReceipt:self withReceiptId: receiptId];
		}	
	
	// Error
	} else if([kResponseFrameError isEqual:command]) {
		if([[self delegate] respondsToSelector:@selector(serverDidSendError:withErrorMessage:detailedErrorMessage:)]) {
			NSString *msg = [headers valueForKey:kResponseHeaderErrorMessage];
			[[self delegate] serverDidSendError:self withErrorMessage: msg detailedErrorMessage: body];
		}		
	}
}

- (void)readFrame {
	[[self socket] readDataToData:[GCDAsyncSocket ZeroData] withTimeout:-1 tag:0];
}

#pragma mark -
#pragma mark AsyncSocketDelegate


- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port {
    if (doAutoconnect) {
		[self loginToServer];
	}
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    
#ifdef GLOBAL_DEBUG_LEVEL
    if(GLOBAL_DEBUG_LEVEL >= 10) NSLog(@"socket:%p didReadData:withTag:%@", sock, tag);
#endif
    
	NSData *strData = [data subdataWithRange:NSMakeRange(0, [data length])];
	NSString *msg = [[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding];
    NSMutableArray *contents = (NSMutableArray *)[[msg componentsSeparatedByString:@"\n"] mutableCopy];
	if ([[contents objectAtIndex:0] isEqual:@""]) {
		[contents removeObjectAtIndex:0];
	}
	NSString *command = [[[contents objectAtIndex:0] copy] autorelease];
	NSMutableDictionary *headers = [[[NSMutableDictionary alloc] init] autorelease];
	NSMutableString *body = [[[NSMutableString alloc] init] autorelease];
	BOOL hasHeaders = NO;
    [contents removeObjectAtIndex:0];
	for (NSString *line in contents) {
		if (hasHeaders) {
			[body appendString:line];
		} else {
			if ([line isEqual:@""]) {
				hasHeaders = YES;
			} else {
				// message-id can look like this: message-id:ID:macbook-pro.local-50389-1237007652070-5:6:-1:1:1
				NSMutableArray *parts = [NSMutableArray arrayWithArray:[line componentsSeparatedByString:@":"]];
				// key ist the first part
				NSString *key = [parts objectAtIndex:0];
				[parts removeObjectAtIndex:0];
				[headers setObject:[parts componentsJoinedByString:@":"] forKey:key];
			}
		}
	}
	[msg release];
	[self receiveFrame:command headers:headers body:body];
	[self readFrame];
	[contents release];
}


- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    connected = FALSE;
    // NSLog(@"CRVStompClient FAIL - %@ %i: %@)", [error domain], [error code], [error localizedDescription]);    
	if([[self delegate] respondsToSelector:@selector(stompClientDidDisconnect:)]) {
		[[self delegate] stompClientDidDisconnect: self];
	}
}

#pragma mark -
#pragma mark Memory management
-(void) dealloc {
	delegate = nil;
	
	CRV_RELEASE_SAFELY(passcode);
	CRV_RELEASE_SAFELY(login);
	CRV_RELEASE_SAFELY(host);
	CRV_RELEASE_SAFELY(socket);

	[super dealloc];
}

@end
