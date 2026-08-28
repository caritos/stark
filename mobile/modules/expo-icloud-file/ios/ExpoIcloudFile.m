#import "ExpoIcloudFile.h"
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <React/RCTUtils.h>

static NSString *const kTodoFileName = @"todo.txt";

@interface ExpoIcloudFile () <UIDocumentPickerDelegate>
@property (nonatomic, copy, nullable) RCTPromiseResolveBlock pickResolve;
@property (nonatomic, copy, nullable) RCTPromiseRejectBlock pickReject;
@end

@implementation ExpoIcloudFile

RCT_EXPORT_MODULE();

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

#pragma mark - pickFolder

RCT_EXPORT_METHOD(pickFolder:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  if (self.pickResolve || self.pickReject) {
    reject(@"PICKER_BUSY", @"A folder picker is already open.", nil);
    return;
  }

  // Open mode (not exporting mode) so we get a handle to the folder itself
  // without writing anything into it — the caller inspects the folder for a
  // pre-existing todo.txt (checkExistingFile) before deciding what to write
  // (finalizeFile). Exporting mode used to hand the destination collision
  // entirely to iOS, silently replacing or renaming any existing file before
  // this code ever ran.
  UIDocumentPickerViewController *picker =
    [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFolder ]];
  picker.delegate = self;
  picker.modalPresentationStyle = UIModalPresentationFormSheet;

  self.pickResolve = resolve;
  self.pickReject = reject;

  UIViewController *root = RCTPresentedViewController();
  [root presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
  didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
  RCTPromiseResolveBlock resolve = self.pickResolve;
  RCTPromiseRejectBlock reject = self.pickReject;
  self.pickResolve = nil;
  self.pickReject = nil;

  NSURL *folderURL = urls.firstObject;
  if (!folderURL) {
    if (reject) reject(@"PICK_FAILED", @"No folder was picked.", nil);
    return;
  }

  // folderURL is security-scoped for locations outside the app's sandbox (which
  // is exactly what an iCloud Drive folder is) — reading its bookmark data
  // without starting access first is denied by the sandbox, surfacing as a
  // misleading "file doesn't exist" error even though the folder is right there.
  BOOL accessing = [folderURL startAccessingSecurityScopedResource];

  NSError *bookmarkError = nil;
  NSData *bookmark = [folderURL bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                          includingResourceValuesForKeys:nil
                                           relativeToURL:nil
                                                   error:&bookmarkError];

  if (accessing) [folderURL stopAccessingSecurityScopedResource];

  if (!bookmark) {
    if (reject) reject(@"BOOKMARK_FAILED", bookmarkError.localizedDescription ?: @"Could not create a bookmark for the picked folder.", bookmarkError);
    return;
  }

  if (resolve) {
    resolve(@{
      @"folderBookmark": [bookmark base64EncodedStringWithOptions:0],
      @"name": folderURL.lastPathComponent ?: @"iCloud Drive",
    });
  }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
  RCTPromiseRejectBlock reject = self.pickReject;
  self.pickResolve = nil;
  self.pickReject = nil;
  if (reject) reject(@"CANCELLED", @"The user cancelled the picker.", nil);
}

#pragma mark - Bookmark resolution

- (nullable NSURL *)resolveBookmark:(NSString *)base64Bookmark error:(NSError **)error
{
  NSData *data = [[NSData alloc] initWithBase64EncodedString:base64Bookmark options:0];
  if (!data) {
    if (error) {
      *error = [NSError errorWithDomain:@"ExpoIcloudFile"
                                    code:1
                                userInfo:@{ NSLocalizedDescriptionKey: @"Malformed bookmark." }];
    }
    return nil;
  }
  BOOL isStale = NO;
  NSURL *url = [NSURL URLByResolvingBookmarkData:data
                                          options:0
                                    relativeToURL:nil
                              bookmarkDataIsStale:&isStale
                                            error:error];
  if (url && isStale) {
    if (error) {
      *error = [NSError errorWithDomain:@"ExpoIcloudFile"
                                    code:2
                                userInfo:@{ NSLocalizedDescriptionKey: @"The iCloud Drive bookmark is stale and needs to be re-picked." }];
    }
    return nil;
  }
  return url;
}

#pragma mark - readFile

RCT_EXPORT_METHOD(readFile:(NSString *)bookmark
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *resolveError = nil;
    NSURL *url = [self resolveBookmark:bookmark error:&resolveError];
    if (!url) {
      reject(@"BOOKMARK_STALE", resolveError.localizedDescription ?: @"Could not resolve the iCloud Drive location.", resolveError);
      return;
    }

    BOOL accessing = [url startAccessingSecurityScopedResource];

    NSNumber *isUbiquitous = nil;
    [url getResourceValue:&isUbiquitous forKey:NSURLIsUbiquitousItemKey error:nil];
    if ([isUbiquitous boolValue]) {
      NSError *downloadError = nil;
      BOOL downloadStarted = [[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:url error:&downloadError];
      if (downloadStarted) {
        for (int i = 0; i < 60; i++) {
          id status = nil;
          [url getResourceValue:&status forKey:NSURLUbiquitousItemDownloadingStatusKey error:nil];
          if (status && ![status isEqual:NSURLUbiquitousItemDownloadingStatusNotDownloaded]) break;
          [NSThread sleepForTimeInterval:0.5];
        }
      }
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
      if (accessing) [url stopAccessingSecurityScopedResource];
      reject(@"FILE_NOT_FOUND", @"The todo.txt file no longer exists at the saved location.", nil);
      return;
    }

    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block NSString *content = nil;
    __block NSError *readError = nil;
    NSError *coordinatorError = nil;
    [coordinator coordinateReadingItemAtURL:url options:0 error:&coordinatorError byAccessor:^(NSURL *newURL) {
      content = [NSString stringWithContentsOfURL:newURL encoding:NSUTF8StringEncoding error:&readError];
    }];

    if (accessing) [url stopAccessingSecurityScopedResource];

    NSError *finalError = coordinatorError ?: readError;
    if (finalError) {
      reject(@"READ_FAILED", finalError.localizedDescription, finalError);
      return;
    }
    resolve(content ?: @"");
  });
}

#pragma mark - writeFile

RCT_EXPORT_METHOD(writeFile:(NSString *)bookmark
                  content:(NSString *)content
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *resolveError = nil;
    NSURL *url = [self resolveBookmark:bookmark error:&resolveError];
    if (!url) {
      reject(@"BOOKMARK_STALE", resolveError.localizedDescription ?: @"Could not resolve the iCloud Drive location.", resolveError);
      return;
    }

    BOOL accessing = [url startAccessingSecurityScopedResource];

    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block NSError *writeError = nil;
    NSError *coordinatorError = nil;
    [coordinator coordinateWritingItemAtURL:url
                                     options:NSFileCoordinatorWritingForReplacing
                                       error:&coordinatorError
                                  byAccessor:^(NSURL *newURL) {
      [content writeToURL:newURL atomically:NO encoding:NSUTF8StringEncoding error:&writeError];
    }];

    if (accessing) [url stopAccessingSecurityScopedResource];

    NSError *finalError = coordinatorError ?: writeError;
    if (finalError) {
      reject(@"WRITE_FAILED", finalError.localizedDescription, finalError);
      return;
    }
    resolve(nil);
  });
}

#pragma mark - checkExistingFile

RCT_EXPORT_METHOD(checkExistingFile:(NSString *)folderBookmark
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *resolveError = nil;
    NSURL *folderURL = [self resolveBookmark:folderBookmark error:&resolveError];
    if (!folderURL) {
      reject(@"BOOKMARK_STALE", resolveError.localizedDescription ?: @"Could not resolve the iCloud Drive location.", resolveError);
      return;
    }

    BOOL accessing = [folderURL startAccessingSecurityScopedResource];
    NSURL *fileURL = [folderURL URLByAppendingPathComponent:kTodoFileName];

    if (![[NSFileManager defaultManager] fileExistsAtPath:fileURL.path]) {
      if (accessing) [folderURL stopAccessingSecurityScopedResource];
      resolve(@{ @"exists": @NO, @"content": [NSNull null] });
      return;
    }

    NSNumber *isUbiquitous = nil;
    [fileURL getResourceValue:&isUbiquitous forKey:NSURLIsUbiquitousItemKey error:nil];
    if ([isUbiquitous boolValue]) {
      NSError *downloadError = nil;
      BOOL downloadStarted = [[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:fileURL error:&downloadError];
      if (downloadStarted) {
        for (int i = 0; i < 60; i++) {
          id status = nil;
          [fileURL getResourceValue:&status forKey:NSURLUbiquitousItemDownloadingStatusKey error:nil];
          if (status && ![status isEqual:NSURLUbiquitousItemDownloadingStatusNotDownloaded]) break;
          [NSThread sleepForTimeInterval:0.5];
        }
      }
    }

    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block NSString *content = nil;
    __block NSError *readError = nil;
    NSError *coordinatorError = nil;
    [coordinator coordinateReadingItemAtURL:fileURL options:0 error:&coordinatorError byAccessor:^(NSURL *newURL) {
      content = [NSString stringWithContentsOfURL:newURL encoding:NSUTF8StringEncoding error:&readError];
    }];

    if (accessing) [folderURL stopAccessingSecurityScopedResource];

    NSError *finalError = coordinatorError ?: readError;
    if (finalError) {
      reject(@"READ_FAILED", finalError.localizedDescription, finalError);
      return;
    }
    resolve(@{ @"exists": @YES, @"content": content ?: @"" });
  });
}

#pragma mark - finalizeFile

RCT_EXPORT_METHOD(finalizeFile:(NSString *)folderBookmark
                  content:(NSString *)content
                  overwrite:(BOOL)overwrite
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSError *resolveError = nil;
    NSURL *folderURL = [self resolveBookmark:folderBookmark error:&resolveError];
    if (!folderURL) {
      reject(@"BOOKMARK_STALE", resolveError.localizedDescription ?: @"Could not resolve the iCloud Drive location.", resolveError);
      return;
    }

    BOOL accessing = [folderURL startAccessingSecurityScopedResource];
    NSURL *fileURL = [folderURL URLByAppendingPathComponent:kTodoFileName];
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:fileURL.path];

    if (overwrite || !fileExists) {
      NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
      __block NSError *writeError = nil;
      NSError *coordinatorError = nil;
      [coordinator coordinateWritingItemAtURL:fileURL
                                       options:NSFileCoordinatorWritingForReplacing
                                         error:&coordinatorError
                                    byAccessor:^(NSURL *newURL) {
        [content writeToURL:newURL atomically:NO encoding:NSUTF8StringEncoding error:&writeError];
      }];

      NSError *finalError = coordinatorError ?: writeError;
      if (finalError) {
        if (accessing) [folderURL stopAccessingSecurityScopedResource];
        reject(@"WRITE_FAILED", finalError.localizedDescription, finalError);
        return;
      }
    }

    NSError *bookmarkError = nil;
    NSData *bookmark = [fileURL bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                          includingResourceValuesForKeys:nil
                                           relativeToURL:nil
                                                   error:&bookmarkError];

    if (accessing) [folderURL stopAccessingSecurityScopedResource];

    if (!bookmark) {
      reject(@"BOOKMARK_FAILED", bookmarkError.localizedDescription ?: @"Could not create a bookmark for the todo.txt file.", bookmarkError);
      return;
    }
    resolve(@{ @"bookmark": [bookmark base64EncodedStringWithOptions:0] });
  });
}

@end
