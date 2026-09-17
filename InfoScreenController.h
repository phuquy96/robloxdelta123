//
//  InfoScreenController.h
//  RobloxMobile
//
//  Copyright (c) 2014 ROBLOX. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NonRotatableViewController.h"

#import "WKWebView+RBXWKWebView.h"

@interface InfoScreenController : NonRotatableViewController <WKNavigationDelegate>
@property (nonatomic, strong) IBOutlet UITextView *txtDeviceInfo;
@property (nonatomic, strong) IBOutlet UITextView *txtRobloxInfo;
@end
