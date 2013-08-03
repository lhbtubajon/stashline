//
//  ViewController.m
//  FinanceLine
//
//  Created by Tristan Hume on 2013-06-18.
//  Copyright (c) 2013 Tristan Hume. All rights reserved.
//

#import "TimelineViewController.h"
#import "TimelineTrackView.h"
#import "LineGraphTrack.h"
#import "AnnuityTrackView.h"
#import "DividerTrackView.h"
#import "StatusTrackView.h"
#import "Constants.h"

#include <stdlib.h>

#define kDefaultIncomeTracks 2
#define kDefaultExpenseTracks 3
#define kAnnuityTrackHeight 50.0
#define kLoadOnStart

@interface TimelineViewController ()

@end

@implementation TimelineViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
  currentSelection = nil;
  [self.fileNameField setText:@"Main"];

  // Load or create model
  model = nil;
  [self loadModel];
}

- (void)addDivider {
  TrackView *divider = [[DividerTrackView alloc] initWithFrame:CGRectZero];
  [self.timeLine addTrack:divider withHeight:2.0];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationLandscapeLeft) ||
        (interfaceOrientation == UIInterfaceOrientationLandscapeRight);
}

#pragma mark Persistence

- (NSString *) pathForDataFile
{
  NSFileManager *fileManager = [NSFileManager defaultManager];

  NSString *folder = @"~/Documents";
  folder = [folder stringByExpandingTildeInPath];

  if ([fileManager fileExistsAtPath:folder] == NO){
    [fileManager createDirectoryAtPath:folder withIntermediateDirectories:NO attributes:nil error:nil];
  }

  NSString *fileName = [self.fileNameField text];
  if([fileName isEqualToString:@""]) return nil;
  fileName = [fileName stringByAppendingString:@".stashLine"];
  
  return [folder stringByAppendingPathComponent: fileName];
}

- (void)saveModel {
  NSString *path = [self pathForDataFile];
  if(path != nil)
    [NSKeyedArchiver archiveRootObject:model toFile: path];
}

- (void)loadModel {
#ifdef kLoadOnStart
  NSString *path = [self pathForDataFile];
  if(path != nil) {
    model = [NSKeyedUnarchiver unarchiveObjectWithFile: path];
  }
#endif
  if (model == nil) {
    model = [self newModel];
  }

  [self loadTracks];
}

- (FinanceModel*)newModel {
  FinanceModel *m = [[FinanceModel alloc] init];

  for (int i = 0; i < kDefaultIncomeTracks; ++i) {
    DataTrack *track = [[DataTrack alloc] init];
    [m.incomeTracks addObject:track];
  }

  for (int i = 0; i < kDefaultExpenseTracks; ++i) {
    DataTrack *track = [[DataTrack alloc] init];
    [m.expenseTracks addObject:track];
  }

  return m;
}

- (void)loadTracks {
  [self.timeLine clearTracks];

  LineGraphTrack *stashTrack = [[LineGraphTrack alloc] initWithFrame:CGRectZero];
  stashTrack.data = model.stashTrack;
  [self.timeLine addTrack:stashTrack withHeight:150.0];

  TimelineTrackView *timeTrack = [[TimelineTrackView alloc] initWithFrame:CGRectZero];
  timeTrack.status = model.statusTrack;
  [self.timeLine addTrack:timeTrack withHeight:100.0];

  [self addDivider];

  for (DataTrack *track in model.incomeTracks) {
    AnnuityTrackView *trackView = [[AnnuityTrackView alloc] initWithFrame:CGRectZero];
    trackView.data = track;
    trackView.selectionDelegate = self;
    [self.timeLine addTrack:trackView withHeight:kAnnuityTrackHeight];
    [self addDivider];
  }

  for (DataTrack *track in model.expenseTracks) {
    AnnuityTrackView *trackView = [[AnnuityTrackView alloc] initWithFrame:CGRectZero];
    trackView.data = track;
    trackView.hue = 0.083;
    trackView.selectionDelegate = self;
    [self.timeLine addTrack:trackView withHeight:kAnnuityTrackHeight];
    [self addDivider];
  }
  
  [self updateParameterFields];
}

#pragma mark File Management

- (IBAction)loadFile {
  [self loadModel];
}

#pragma mark Operations

- (IBAction)cutJobAtRetirement {
  [model cutJobAtRetirement];
  [self.timeLine redrawTracks];
  [self saveModel];
}

- (IBAction)aboutMe {
  NSURL *url = [NSURL URLWithString:@"http://thume.ca/"];
  [[UIApplication sharedApplication] openURL:url];
}

#pragma mark Investment parameters

- (void)updateParameterField:(UITextField*)field toPercent:(double)value {
  NSString *str = [self stringForAmount:value * 100.0];
  [field setText:str];
}

- (void)updateParameterFields {
  [self updateParameterField:self.growthRateField toPercent:model.growthRate];
  [self updateParameterField:self.dividendRateField toPercent:model.dividendRate];
  [self updateParameterField:self.safeWithdrawalField toPercent:model.safeWithdrawalRate];
}

- (IBAction)parameterFieldChanged:(UITextField*)sender {
  double value = [self parseValue:[sender text]] / 100.0;
  
  if (sender == self.safeWithdrawalField) {
    model.safeWithdrawalRate = value;
  } else if(sender == self.dividendRateField) {
    model.dividendRate = value;
  } else if(sender == self.growthRateField) {
    model.growthRate = value;
  }
  
  [self updateParameterFields];
  [model recalc];
  [self.timeLine redrawTracks];
  [self saveModel];
}

#pragma mark Selections

- (void)setSelection:(Selection *)sel onTrack:(DataTrack *)track {
  // clear selection on other track
  if (currentSelection != nil && currentSelection != sel) {
    [currentSelection clear];
  }

  currentSelection = sel;
  selectedTrack = track;

  if ([currentSelection isEmpty]) {
    [self clearSelection];
    return;
  }

  // calculate selection average
  double total = 0.0;
  double *data = [selectedTrack dataPtr];
  for (int i = currentSelection.start; i <= currentSelection.end; ++i)
    total += data[i];
  double average = total / (currentSelection.end - currentSelection.start + 1);

  [self updateAmountFields:average];
  [self.timeLine redrawTracks];
}

- (IBAction)clearSelection {
  [currentSelection clear];
  currentSelection = nil;
  selectedTrack = nil;

  [self.monthlyCost setText:@""];
  [self.yearlyCost setText:@""];
  [self.dailyCost setText:@""];
  [self.workDailyCost setText:@""];
  [self.workHourlyCost setText:@""];

  [self.timeLine redrawTracks];
}

- (IBAction)expandSelectionToEnd {
  if (currentSelection != nil && currentSelection.start > 0) {
    currentSelection.end = kMaxMonth;
  }
  [self.timeLine redrawTracks];
}

- (NSString *)stringForAmount:(double)amount {
  return [NSString stringWithFormat:@"%.2f", amount];
}

- (void)setAmount:(double)amount forField:(UITextField*)field {
  NSString *str = [self stringForAmount:amount];
  [field setText:str];
}

- (void)updateAmountFields:(double)monthlyValue {
  [self setAmount:monthlyValue forField:self.monthlyCost];
  [self setAmount:monthlyValue*12.0 forField:self.yearlyCost];
  [self setAmount:monthlyValue/30.4 forField:self.dailyCost];
  [self setAmount:monthlyValue/20.0 forField:self.workDailyCost];
  [self setAmount:monthlyValue/160.0 forField:self.workHourlyCost];
}

- (void)updateSelectionAmount:(double)monthlyValue {
  if (currentSelection == nil || selectedTrack == nil) {
    return;
  }

  [self updateAmountFields:monthlyValue];

  // Set selection
  double *data = [selectedTrack dataPtr];
  for (int i = currentSelection.start; i <= currentSelection.end; ++i)
    data[i] = monthlyValue;
  [selectedTrack recalc];

  // Recalc and render
  [model recalc];
  [self.timeLine redrawTracks];
  [self saveModel];
}

- (double)parseValue: (NSString*)str {
  return [str doubleValue];
}

- (IBAction)selectionAmountChanged: (UITextField*)sender {
  if ([sender.text isEqualToString:@""]) return;
  double value = [self parseValue:[sender text]];

  // convert to a monthly cost
  if (sender == self.yearlyCost) {
    value /= 12.0;
  } else if(sender == self.dailyCost) {
    value *= 30.4;
  } else if(sender == self.workDailyCost) {
    value *= 5.0*4.0;
  } else if(sender == self.workHourlyCost) {
    value *= 40*4.0;
  }

  [self updateSelectionAmount: value];
}

- (IBAction)zeroSelection {
  [self updateSelectionAmount:0.0];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
  [textField resignFirstResponder];
  return NO;
}

- (void)viewDidUnload {
  [self setGrowthRateField:nil];
  [self setDividendRateField:nil];
  [self setSafeWithdrawalField:nil];
  [super viewDidUnload];
}
@end
