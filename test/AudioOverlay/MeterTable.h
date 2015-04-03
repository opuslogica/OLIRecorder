//
//  MeterTable.h
//  AudioStreaming
//
//  Created by Ed Gamble on 4/2/15.
//  Copyright (c) 2015 Opus Logica Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MeterTable : NSObject {
  float	mMinDecibels;
  float	mDecibelResolution;
  float	mScaleFactor;
  float	*mTable; 
}

- (float) valueAt: (float) inDecibels;

- (MeterTable *) initWithMinDecibels: (float) inMinDecibels
                           tableSize: (size_t) inTableSize
                                root: (float) inRoot;
@end

#if 0

MeterTable(float inMinDecibels = -80., size_t inTableSize = 400, float inRoot = 2.0);
~MeterTable();

float ValueAt(float inDecibels)
{
		if (inDecibels < mMinDecibels) return  0.;
		if (inDecibels >= 0.) return 1.;
		int index = (int)(inDecibels * mScaleFactor);
		return mTable[index];
}
private:
float	mMinDecibels;
float	mDecibelResolution;
float	mScaleFactor;
float	*mTable;
};
#endif
