//
//  MeterTable.m
//  AudioStreaming
//
//  Created by Ed Gamble on 4/2/15.
//  Copyright (c) 2015 Opus Logica Inc. All rights reserved.
//
#import "MeterTable.h"


@implementation MeterTable

- (double) DbToAmp: (double) inDb
{ return pow(10., 0.05 * inDb); }

- (float) valueAt: (float) inDecibels {
  if (inDecibels < mMinDecibels) return  0.;
  if (inDecibels >= 0.) return 1.;

  int index = (int)(inDecibels * mScaleFactor);
  return mTable[index];
}


- (MeterTable *) initWithMinDecibels: (float) inMinDecibels
                           tableSize: (size_t) inTableSize
                                root: (float) inRoot {
  mMinDecibels = inMinDecibels;
  mDecibelResolution = mMinDecibels / (inTableSize - 1);
  mScaleFactor = 1 / mDecibelResolution;
  
  if (inMinDecibels >= 0.)
  {
    printf("MeterTable inMinDecibels must be negative");
    return self;
  }

  mTable = (float*)malloc(inTableSize*sizeof(float));
  
  double minAmp = [self DbToAmp: inMinDecibels];
  double ampRange = 1. - minAmp;
  double invAmpRange = 1. / ampRange;
  
  double rroot = 1. / inRoot;
  for (size_t i = 0; i < inTableSize; ++i) {
    double decibels = i * mDecibelResolution;
    double amp = [self DbToAmp: decibels];
    double adjAmp = (amp - minAmp) * invAmpRange;
    mTable[i] = pow(adjAmp, rroot);
  }

  return self;
}

@end

#if 0
inline double DbToAmp(double inDb)
{
  return pow(10., 0.05 * inDb);
}

MeterTable::MeterTable(float inMinDecibels, size_t inTableSize, float inRoot)
: mMinDecibels(inMinDecibels),
mDecibelResolution(mMinDecibels / (inTableSize - 1)),
mScaleFactor(1. / mDecibelResolution)
{
  if (inMinDecibels >= 0.)
  {
    printf("MeterTable inMinDecibels must be negative");
    return;
  }
  
  mTable = (float*)malloc(inTableSize*sizeof(float));
  
  double minAmp = DbToAmp(inMinDecibels);
  double ampRange = 1. - minAmp;
  double invAmpRange = 1. / ampRange;
  
  double rroot = 1. / inRoot;
  for (size_t i = 0; i < inTableSize; ++i) {
    double decibels = i * mDecibelResolution;
    double amp = DbToAmp(decibels);
    double adjAmp = (amp - minAmp) * invAmpRange;
    mTable[i] = pow(adjAmp, rroot);
  }
}

MeterTable::~MeterTable()
{
  free(mTable);
}
#endif