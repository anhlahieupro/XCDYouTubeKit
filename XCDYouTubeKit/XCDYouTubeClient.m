//
//  Copyright (c) 2013-2016 Cédric Luthi. All rights reserved.
//

#import "XCDYouTubeClient.h"

#import "XCDYouTubeVideoOperation.h"

@interface XCDYouTubeClient ()
@property (nonatomic, strong) NSOperationQueue *queue;
@end

@implementation XCDYouTubeClient

@synthesize languageIdentifier = _languageIdentifier;

+ (instancetype) defaultClient
{
	static XCDYouTubeClient *defaultClient;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		defaultClient = [self new];
	});
	return defaultClient;
}

- (instancetype) init
{
	return [self initWithLanguageIdentifier:nil];
}

- (instancetype) initWithLanguageIdentifier:(NSString *)languageIdentifier
{
	if (!(self = [super init]))
		return nil; // LCOV_EXCL_LINE
	
	_languageIdentifier = ^{
		return languageIdentifier ?: ^{
			NSArray *preferredLocalizations = [[NSBundle mainBundle] preferredLocalizations];
			NSString *preferredLocalization = preferredLocalizations.firstObject ?: @"en";
			return [NSLocale canonicalLanguageIdentifierFromString:preferredLocalization] ?: @"en";
		}();
	}();
	
	_queue = [NSOperationQueue new];
	_queue.maxConcurrentOperationCount = 6; // paul_irish: Chrome re-confirmed that the 6 connections-per-host limit is the right magic number: https://code.google.com/p/chromium/issues/detail?id=285567#c14 [https://twitter.com/paul_irish/status/422808635698212864]
	_queue.name = NSStringFromClass(self.class);
	
	return self;
}

- (id<XCDYouTubeOperation>) getVideoWithIdentifier:(NSString *)videoIdentifier cookies:(NSArray<NSHTTPCookie *> *)cookies customPatterns:(NSArray<NSString *> *)customPatterns completionHandler:(void (^)(XCDYouTubeVideo * _Nullable, NSError * _Nullable))completionHandler
{
	if (!completionHandler)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"The `completionHandler` argument must not be nil." userInfo:nil];
	
	XCDYouTubeVideoOperation *operation = [[XCDYouTubeVideoOperation alloc] initWithVideoIdentifier:videoIdentifier languageIdentifier:self.languageIdentifier cookies:cookies customPatterns:customPatterns];
	operation.completionBlock = ^{
		[[NSOperationQueue mainQueue] addOperationWithBlock:^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
			if (operation.video || operation.error)
			{
				NSAssert(!(operation.video && operation.error), @"One of `video` or `error` must be nil.");
				completionHandler(operation.video, operation.error);
			}
			else
			{
				NSAssert(operation.isCancelled, @"Both `video` and `error` can not be nil if the operation was not canceled.");
			}
			operation.completionBlock = nil;
#pragma clang diagnostic pop
		}];
	};
	[self.queue addOperation:operation];
	return operation;
}

- (id<XCDYouTubeOperation>) getVideoWithIdentifier:(NSString *)videoIdentifier completionHandler:(void (^)(XCDYouTubeVideo * __nullable video, NSError * __nullable error))completionHandler
{
	return [self getVideoWithIdentifier:videoIdentifier cookies:nil customPatterns:nil  completionHandler:completionHandler];
}

- (id<XCDYouTubeOperation>) getVideoWithIdentifier:(NSString *)videoIdentifier cookies:(NSArray<NSHTTPCookie *> *)cookies completionHandler:(void (^)(XCDYouTubeVideo * _Nullable, NSError * _Nullable))completionHandler
{
	return [self getVideoWithIdentifier:videoIdentifier cookies:cookies customPatterns:nil  completionHandler:completionHandler];
}

- (XCDYouTubeVideoQueryOperation *)queryVideo:(XCDYouTubeVideo *)video cookies:(NSArray<NSHTTPCookie *> *)cookies completionHandler:(void (^)(NSDictionary * _Nonnull, NSError * _Nullable, NSDictionary<id,NSError *> * _Nonnull))completionHandler
{
	return [self queryVideo:video streamURLsToQuery:nil options:nil cookies:cookies completionHandler:completionHandler];
}

- (XCDYouTubeVideoQueryOperation *)queryVideo:(XCDYouTubeVideo *)video streamURLsToQuery:(NSDictionary<id,NSURL *> *)streamURLsToQuery options:(NSDictionary *)options cookies:(NSArray<NSHTTPCookie *> *)cookies completionHandler:(void (^)(NSDictionary * _Nullable, NSError * _Nullable, NSDictionary<id,NSError *> * _Nullable))completionHandler
{
	if (!completionHandler)
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"The `completionHandler` argument must not be nil." userInfo:nil];
	
	XCDYouTubeVideoQueryOperation *operation = [[XCDYouTubeVideoQueryOperation alloc]initWithVideo:video streamURLsToQuery:streamURLsToQuery options:options cookies:cookies];
	operation.completionBlock = ^{
		[[NSOperationQueue mainQueue] addOperationWithBlock:^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
			if (operation.streamURLs || operation.error)
			{
				NSAssert(!(operation.streamURLs && operation.error), @"One of `streamURLs` or `error` must be nil.");
				completionHandler(operation.streamURLs, operation.error, operation.streamErrors);
			} else
			{
				NSAssert(operation.isCancelled, @"Both `streamURLs` and `error` can not be nil if the operation was not canceled.");
			}
			operation.completionBlock = nil;
#pragma clang diagnostic pop
		}];
	};
	
	[self.queue addOperation:operation];
	return operation;
}

// Hieudinh dd/MM/yyyy 30/04/2020
- (id<XCDYouTubeOperation>)handleGetVideoWithIdentifier:(NSString *)videoIdentifier completionHandler:(void (^)(AVAsset *__nullable asset, NSURL *__nullable url))completionHandler {
	
	__weak XCDYouTubeClient *weakSelf = self;
	
	return [self getVideoWithIdentifier:videoIdentifier completionHandler:^(XCDYouTubeVideo * _Nullable video, NSError * _Nullable error) {
		
		if (error == nil && video) {
			
			NSArray *array = @[@(XCDYouTubeVideoQualityHD720),
							   @(XCDYouTubeVideoQualityMedium360),
							   @(XCDYouTubeVideoQualitySmall240)];
			
			dispatch_group_t group = dispatch_group_create();
			__block BOOL isError = YES;
			
			for (unsigned long i = 0; i < array.count; i++) {
				
				NSURL *url = video.streamURLs[array[i]];
				
				if (url) {
					
					dispatch_group_enter(group);
					
					[weakSelf getAssetWithUrl:url completionHandler:^(AVAsset * _Nullable asset) {
						
						if (asset && isError) {
							isError = NO;
							completionHandler(asset, url);
						}
						
						dispatch_group_leave(group);
						
					}];
				}
			}
			
			dispatch_group_notify(group,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ {
				if (isError) {
					completionHandler(nil, nil);
				}
			});
			
			return;
		}
		
		completionHandler(nil, nil);
	}];
}

// Hieudinh dd/MM/yyyy 30/04/2020
- (void)getAssetWithUrl:(NSURL *)url completionHandler:(void (^)(AVAsset *__nullable asset))completionHandler {
	if (url) {
		AVAsset *asset = [AVAsset assetWithURL:url];
		
		NSString *playable = @"playable";
		[asset loadValuesAsynchronouslyForKeys:@[playable] completionHandler:^{
			NSError *error;
			AVKeyValueStatus status = [asset statusOfValueForKey:playable error:&error];
			
			if (error) {
				[asset cancelLoading];
				completionHandler(nil);
				return;
			}
			
			switch (status) {
				case AVKeyValueStatusLoaded: {
					
					dispatch_async(dispatch_get_main_queue(), ^{
						completionHandler(asset);
					});
					break;
					
				}
					
				case AVKeyValueStatusUnknown:
				case AVKeyValueStatusLoading:
				case AVKeyValueStatusFailed:
				case AVKeyValueStatusCancelled: {
					
					dispatch_async(dispatch_get_main_queue(), ^{
						
						completionHandler(nil);
						[asset cancelLoading];
						
					});
					break;
					
				}
			}
		}];
	}
}

@end
